# ARMA Reforger Player Logger

A Bash script that monitors ARMA Reforger server logs and sends authenticated player information (name, IP, GUID) to a Discord webhook (The webhook is optional, you can disable this feature in the script).
Handles names with spaces and Unicode characters, and escapes Discord markdown.

## Requirements

- Bash 4+
- `curl`
- `jq` (for safe JSON escaping)

## Installation

1. Copy `reforger_logger.sh` into your ARMA Reforger server `Logs/` directory.

`cp reforger_logger.sh /path/to/ArmaReforgerServer/Logs/`

2. Edit the script and configure your Discord webhook URL
`nano /path/to/ArmaReforgerServer/Logs/reforger_logger.sh`

##Usage
Run the script as a daemon

`cd /path/to/ArmaReforgerServer/Logs`
`nohup ./reforger_logger.sh &`

The script will monitor console.log files and send notifications to the configured Discord webhook when players authenticate.


#State

Temporary state is stored in /tmp/areforger_logger to avoid duplicate notifications.

Webhook results are logged to loggerwebhook.log in the same directory as the script.

#Notes

Ensure jq is installed for proper JSON escaping.
Discord webhook URL must be valid.
