#!/bin/bash

# Load alert config
CONFIG_FILE="/etc/sysmonitor.conf"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "ERROR: Config file $CONFIG_FILE not found. Please create it and define ALERT_EMAIL." >&2
  exit 1
fi

# Validate email
if [ -z "$ALERT_EMAIL" ]; then
  echo "ERROR: ALERT_EMAIL is not set in $CONFIG_FILE" >&2
  exit 1
fi

# Alert config
ALERT_LOG="/var/log/sysmonitor_alerts.log"
MAIL_LOG="/var/log/sysmonitor_mail_errors.log"

# Check if `mail` is installed
if ! command -v mail >/dev/null 2>&1; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: 'mail' command not found. Please install mailutils or similar." >> "$ALERT_LOG"
  exit 1
fi

send_alert() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local alert_msg="$timestamp ALERT:\n$message"

  # Log alert to file
  echo -e "$alert_msg" | tee -a "$ALERT_LOG"

  # Send mail and capture output & errors
  echo -e "$alert_msg" | /usr/bin/mail -s "Sysmonitor Alert" "$ALERT_EMAIL" 2>> "$MAIL_LOG"

  local mail_status=$?
  if [ $mail_status -ne 0 ]; then
    echo "$timestamp ERROR: mail command failed with status $mail_status" >> "$MAIL_LOG"
  else
    echo "$timestamp INFO: mail sent successfully" >> "$MAIL_LOG"
  fi
}
echo

echo "==========User Login & Activity Audit=========="

echo "INFO: Currently logged-in users:"
who

echo

# Show last real login (excluding system boot entries)
last_login=$(last -F | grep -v "system boot" | head -n 1)
if [ -n "$last_login" ]; then
  echo "INFO: Last login recorded:"
  echo "$last_login"
else
  echo "INFO: No previous login records found."
fi

echo

# Count failed login attempts in the last 1 hour
fail_log=$(journalctl -u ssh --since "$ALERT_LOOKBACK" | grep "Failed password")
# fail_count=$(echo "$fail_log" | wc -l)
fail_log=$(journalctl -u ssh --since "$ALERT_LOOKBACK")
fail_count=$(grep -c "Failed password" <<< "$fail_log")
fail_log=$(grep "Failed password" <<< "$fail_log")

# echo "DEBUG: fail_log content:"
# echo "$fail_log"


if [ "$fail_count" -gt 0 ]; then
  # echo "ALERT: $fail_count failed SSH login attempts in the "$ALERT_LOOKBACK"."
  echo "=====INFO: Preparing alert for $fail_count failed login attempts in the last "$ALERT_LOOKBACK".====="

  # Extract and summarize IPs
  ip_summary=$(echo "$fail_log" | awk '{for (i=1; i<=NF; i++) if ($i == "from") print $(i+1)}' | sort | uniq -c)

  # Get recent attempt timestamps and IPs
  recent_attempts=$(echo "$fail_log" | tail -n 5 | grep -oP 'from \K[\d\.]+')

  echo
  # Build detailed alert message
  alert_msg="Detected $fail_count failed SSH login attempts in the last "$ALERT_LOOKBACK".

Source IPs:
$ip_summary

Recent attempts:
$recent_attempts
"

  # Send and log the alert
  send_alert "$alert_msg"

#if fail_count is 0
else
  echo "INFO: Failed SSH login attempts in the last "$ALERT_LOOKBACK": $fail_count"
fi

echo

COMMAND_COUNT=3
echo "INFO: Recent shell commands from users (up to $COMMAND_COUNT each, filtered for sensitive info):"

getent passwd | while IFS=: read -r username _ uid _ _ _ home shell; do
  if [ "$uid" -ge 1000 ] && [[ "$shell" =~ /(ba)?sh$|zsh$ ]]; then
    echo "-- $username --"
    hist="$home/.bash_history"
    [ ! -f "$hist" ] && hist="$home/.zsh_history"
    if [ -f "$hist" ]; then
      sudo -u "$username" tail -n $COMMAND_COUNT "$hist" 2>/dev/null | grep -v -E 'password|secret|key|token' || echo "No safe history available."
    else
      echo "No safe history available."
    fi
    echo
  fi
done