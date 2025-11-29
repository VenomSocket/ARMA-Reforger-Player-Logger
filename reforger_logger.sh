#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_BASE="$SCRIPT_DIR"
WEBHOOK_URL="HTTPS://YOUR.DISCORD.WEBHOOK.URL.HERE"    # <<< fill in your discord webhook URL
WEBHOOK_LOG="$LOG_BASE/loggerwebhook.log"
DEBUG_NOSEND=0
STATE_DIR="/tmp/areforger_logger"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script dir: $SCRIPT_DIR" >&2
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log base: $LOG_BASE" >&2

mkdir -p "$STATE_DIR"

log_webhook() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$WEBHOOK_LOG"; }
log_info()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2; }

get_timestamp() {
    echo "$1" | grep -oE '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1
}

# escape discord markdown in player names
escape_markdown() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\*/\\*}"
    s="${s//_/\\_}"
    s="${s//\~/\\~}"
    s="${s//\`/\\\`}"
    s="${s//|/\\|}"
    echo "$s"
}

extract_rpl_event() {
    if [[ $1 =~ ServerImpl\ event:\ authenticating\ \(identity=([^,]+),\ address=([^:]+):([0-9]+)\) ]]; then
        echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|$(get_timestamp "$1")"
        return 0
    fi
    return 1
}

# capture full name including spaces
extract_backend_event() {
    if [[ $1 =~ Authenticated\ player:\ rplIdentity=([^ ]+)\ identityId=([^ ]+)\ name=(.*)$ ]]; then
        echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}|$(get_timestamp "$1")"
        return 0
    fi
    return 1
}

send_to_discord() {
    local name="$1" ip="$2" guid="$3"

    [ "$DEBUG_NOSEND" = "1" ] && log_webhook "DEBUG" "Would send: $name | $ip | $guid" && return 0
    [ -z "$WEBHOOK_URL" ] && log_webhook "FAILED" "No webhook URL set" && return 1

    local safe_name="$(escape_markdown "$name")"
    log_info "HIT: $safe_name|$ip|$guid"

    # use jq to safely escape JSON for Discord
    local payload
    payload=$(jq -n --arg content "**$safe_name** | \`$ip\` | \`$guid\`" '{content:$content}')

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d "$payload")

    if [[ "$http_code" == "204" || "$http_code" == "200" ]]; then
        log_webhook "SUCCESS" "Posted: $safe_name | $ip | $guid"
    else
        log_webhook "FAILED" "HTTP $http_code: $safe_name | $ip | $guid"
    fi
}

check_dedup() {
    local guid="$1" ip="$2" name="$3"
    local state_file="$STATE_DIR/player_$guid"
    local state="${ip}|${name}"

    [ -f "$state_file" ] && [ "$(cat "$state_file")" = "$state" ] && return 1

    echo "$state" > "$state_file"
    return 0
}

find_rpl() {
    local rplid="$1"
    local f="$STATE_DIR/rpl_$rplid"
    [ -f "$f" ] || return 1
    local ip=$(cut -d'|' -f2 "$f")
    rm -f "$f"
    echo "$ip"
}

process_log_file() {
    local logfile="$1"
    local count=$(wc -l < "$logfile" 2>/dev/null || echo 0)
    local key=$(basename "$logfile" | md5sum | cut -d' ' -f1)
    local numfile="$STATE_DIR/last_line_num_$key"

    local last=0
    [ -f "$numfile" ] && last=$(cat "$numfile" 2>/dev/null || echo 0)

    [ "$count" -le "$last" ] && return

    echo "$count" > "$numfile"

    tail -n +$((last + 1)) "$logfile" | while read -r line; do
        if rpl=$(extract_rpl_event "$line"); then
            IFS='|' read -r identity ip ts <<< "$rpl"
            echo "$identity|$ip|$ts" > "$STATE_DIR/rpl_$identity"
        fi

        if backend=$(extract_backend_event "$line"); then
            IFS='|' read -r rplid guid name ts <<< "$backend"

            rpl_file="$STATE_DIR/rpl_$rplid"
            if [ -f "$rpl_file" ]; then
                ip=$(cut -d'|' -f2 "$rpl_file")
                rm -f "$rpl_file"

                if [ -n "$ip" ]; then
                    state_file="$STATE_DIR/player_$guid"
                    state="${ip}|${name}"

                    if [ ! -f "$state_file" ] || [ "$(cat "$state_file")" != "$state" ]; then
                        echo "$state" > "$state_file"
                        send_to_discord "$name" "$ip" "$guid"
                    fi
                fi
            fi
        fi
    done
}

find_active_log() {
    find "$LOG_BASE" -maxdepth 2 -name "console.log" -type f | sort -r | head -1
}

main() {
    log_info "Logger started"

    local current_log=""
    local first=true

    while true; do
        local active=$(find_active_log)

        if [ -n "$active" ]; then
            if [ "$current_log" != "$active" ]; then
                [ -n "$current_log" ] && log_info "Switched to new log: $active"
                current_log="$active"

                local count=$(wc -l < "$active" 2>/dev/null || echo 0)
                local key=$(basename "$active" | md5sum | cut -d' ' -f1)
                local numfile="$STATE_DIR/last_line_num_$key"

                if $first; then
                    echo "$count" > "$numfile"
                    log_info "Monitoring: $active (skipped to line $count)"
                    first=false
                else
                    echo "0" > "$numfile"
                    log_info "New log detected, starting from beginning"
                fi
            fi

            process_log_file "$active"
        fi

        sleep 2
    done
}

trap 'rm -rf "$STATE_DIR"; exit 0' SIGTERM SIGINT

main
