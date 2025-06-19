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
fail_log=$(journalctl -u ssh --since "1 hour ago" | grep "Failed password")
fail_count=$(echo "$fail_log" | wc -l)

if [ "$fail_count" -gt 0 ]; then
  echo "ALERT: $fail_count failed SSH login attempts in the last hour."

  # Extract and summarize IPs
  ip_summary=$(echo "$fail_log" | awk '{for (i=1; i<=NF; i++) if ($i == "from") print $(i+1)}' | sort | uniq -c)

  # Get recent attempt timestamps and IPs
  recent_attempts=$(echo "$fail_log" | tail -n 5 | awk '{print $1, $2, $3, $11}')

  # Build detailed alert message
  alert_msg="Detected $fail_count failed SSH login attempts in the past hour.

Source IPs:
$ip_summary

Recent attempts:
$recent_attempts
"

  # Send and log the alert
  send_alert "$alert_msg"
else
  echo "INFO: Failed SSH login attempts in the last hour: $fail_count"
fi

echo

COMMAND_COUNT=3
echo "INFO: Recent shell commands from users (up to $COMMAND_COUNT each, filtered for sensitive info):"

# Get users with UID >= 1000 and valid shell
getent passwd | while IFS=: read -r username _ uid _ _ _ home shell; do
  if [ "$uid" -ge 1000 ] && [[ "$shell" =~ /(ba)?sh$|zsh$ ]] && [[ "$shell" != "/usr/sbin/nologin" ]]; then
    echo "-- $username --"
    user_home=$(eval echo "~$username")
    sudo -u "$username" bash -c "tail -n $COMMAND_COUNT \"$user_home/.bash_history\" 2>/dev/null | grep -v -E 'password|secret|key|token' || echo 'No safe history available.'"
    echo
  fi
done

# Notes:
# - This script is only executable by root or trusted admins to prevent unauthorized access:
#     chmod 700 /path/to/this_script.sh
#     chown root:root /path/to/this_script.sh
#
# - Run this script locally or over a secure SSH connection to protect sensitive data.
#
# - Consider redirecting script output to a secure log file with restricted permissions:
#     /path/to/this_script.sh >> /var/log/sysmonitor.log 2>&1
#     chmod 600 /var/log/sysmonitor.log
#
# - Make sure the alert log file used in the script (e.g., /var/log/sysmonitor_alerts.log) is also secured:
#     touch /var/log/sysmonitor_alerts.log
#     chmod 600 /var/log/sysmonitor_alerts.log
