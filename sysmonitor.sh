#!/bin/bash

#To be safer and avoid sending old alerts, 
# we wil clear the alerts file at the start of your script 
> /tmp/combined_sys_alerts.txt 

LOGFILE="/home/Testmonitor_alerts.log"
MAIL_LOG="/var/log/sysmonitor/mail_errors.log"
USER_LOG_FILE="/var/log/auth.log"
TRACEFILE="/home/monitor_trace.json"

EMAIL_RECIPIENT="replacethisemail@gmail.com"
EMAIL_SUBJECT="System Monitoring Alert"

# Check writable log directory
if [ ! -w "$(dirname "$LOGFILE")" ]; then
    echo "Error: Cannot write to log directory $(dirname "$LOGFILE")" | tee -a "$LOGFILE"
    exit 1
fi

# Check writable trace directory
if [ ! -w "$(dirname "$TRACEFILE")" ]; then
    echo "Error: Cannot write to trace directory $(dirname "$TRACEFILE")" | tee -a "$TRACEFILE"
    exit 1
fi

# Check if `mail` is installed
if ! command -v mail >/dev/null 2>&1; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: 'mail' command not found. Please install mailutils or similar." >> "$LOGFILE"
  exit 1
fi

send_alert() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local alert_msg="$timestamp ALERT:\n$message"

  # Log alert to file
  echo -e "$alert_msg" | tee -a "$LOGFILE"

  # Send mail and capture output & errors
  echo -e "$alert_msg" | /usr/bin/mail -s "Sysmonitor Alert" "$EMAIL_RECIPIENT" 2>> "$MAIL_LOG"

  local mail_status=$?
  if [ $mail_status -ne 0 ]; then
    echo "$timestamp ERROR: mail command failed with status $mail_status" >> "$MAIL_LOG"
  else
    echo "$timestamp INFO: mail sent successfully" >> "$MAIL_LOG"
  fi
}

# Check for required commands
for cmd in awk bc df free ps ss who last; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found" | tee -a "$LOGFILE"
        exit 1
    fi
done


TEMP_TRACE=$(mktemp)
if [ ! -f "$TRACEFILE" ]; then
    echo '{"traceEvents": []}' > "$TRACEFILE"
fi

# Read existing trace events
jq '.' "$TRACEFILE" > "$TEMP_TRACE" || {
    echo "Error: Invalid JSON in $TRACEFILE" | tee -a "$LOGFILE"
    exit 1
}

# Timestamp in microseconds
EPOCH_MICRO=$(($(date +%s%N)/1000))

# CPU Usage
cpu_idle=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1) {print (t-u)/t*100}}' /proc/stat)
cpu_usage=$(echo "100 - $cpu_idle" | bc | awk '{printf "%.1f", $0}')

echo "==== System Monitoring Report ====" | tee -a "$LOGFILE"
echo "Date: $(date)" | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

echo "CPU Usage: $cpu_usage%" | tee -a "$LOGFILE"
if [ $(echo "$cpu_usage > 80" | bc) -eq 1 ]; then
    alert="WARNING: High CPU usage detected: $cpu_usage%"
    echo "$alert" | tee -a "$LOGFILE"
    # send_alert "$alert"
    # Instead of sending email here, we will append to a global alert file or variable so all alerts will be sent in one go
    echo "$alert" >> /tmp/combined_sys_alerts.txt
fi
echo | tee -a "$LOGFILE"

# Memory Usage
mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mem_used=$((mem_total - mem_available))
mem_usage_percent=$((mem_used * 100 / mem_total))
echo "Memory Usage: $((mem_used / 1024)) MB / $((mem_total / 1024)) MB ($mem_usage_percent%)" | tee -a "$LOGFILE"
if [ "$mem_usage_percent" -gt 80 ]; then
    alert="WARNING: High memory usage detected: $mem_usage_percent%"
    echo "$alert" | tee -a "$LOGFILE"
    # send_alert "$alert"
    echo "$alert" >> /tmp/combined_sys_alerts.txt
fi
echo | tee -a "$LOGFILE"

# Prepare new trace events
NEW_EVENTS=$(cat <<EOF
[
  {
    "name": "CPU Usage",
    "cat": "system",
    "ph": "X",
    "ts": $EPOCH_MICRO,
    "dur": 1000000,
    "pid": 1,
    "tid": 1,
    "args": {"usage_percent": "$cpu_usage"}
  },
  {
    "name": "Memory Usage",
    "cat": "system",
    "ph": "X",
    "ts": $EPOCH_MICRO,
    "dur": 1000000,
    "pid": 1,
    "tid": 2,
    "args": {"usage_percent": "$mem_usage_percent"}
  }
]
EOF
)

# Append new events to trace file atomically using jq
jq --argjson new_events "$NEW_EVENTS" '.traceEvents += $new_events' "$TEMP_TRACE" > "$TEMP_TRACE.new" && mv "$TEMP_TRACE.new" "$TRACEFILE"
rm -f "$TEMP_TRACE"

echo | tee -a "$LOGFILE"


# Disk Usage
disk_usage=$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')
echo "Disk Usage on /: $disk_usage%" | tee -a "$LOGFILE"
if [ "$disk_usage" -gt 80 ]; then
    alert="WARNING: Disk usage above 80%: $disk_usage%"
    echo "$alert" | tee -a "$LOGFILE"
    # send_alert "$alert"
    echo "$alert" >> /tmp/combined_sys_alerts.txt
fi
echo | tee -a "$LOGFILE"

# Uptime
echo "System Uptime:" | tee -a "$LOGFILE"
uptime -p | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"


# Active network connections (top 10, established)
echo "Active network connections (top 10, established):" | tee -a "$LOGFILE"
ss -tuna state established | head -n 10 | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"


#Top 5 CPU-intensive processes
echo "INFO: Top 5 memory-intensive processes:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6
echo

# User Login & Activity Audit
echo "INFO: Currently logged-in users:"
w
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

# Set fallback if variable isn't provided
ALERT_LOOKBACK="${ALERT_LOOKBACK:-10 days ago}"

# Get timestamp in ISO 8601 (matching log format)
cutoff_timestamp=$(date --date="$ALERT_LOOKBACK" --iso-8601=seconds)

# Read auth log and filter failed ssh logins after cutoff time
fail_log=$(sudo awk -v cutoff="$cutoff_timestamp" '
  {
    split($1, log_date, "T")
    if (length(log_date) && $0 ~ /sshd.*Failed password/) {
      log_time = $1
      if (log_time >= cutoff) print
    }
  }
' /var/log/auth.log)

fail_count=$(echo "$fail_log" | wc -l)
if [ "$fail_count" -gt 0 ]; then
  ip_summary=$(echo "$fail_log" |
                 awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' |
                 sort | uniq -c | sort -nr)

  readable_ips="${ip_summary:-None detected.}"

  alert_msg=$(printf "
Failed SSH login attempts Detected:

Source IPs:
%s
" "$readable_ips")

  # Append to combined alerts file instead of sending immediately
  echo "$alert_msg" >> /tmp/combined_sys_alerts.txt
else
  echo "✅ INFO: No failed SSH login attempts since $ALERT_LOOKBACK."
fi

# Append alerts to a file and send one email
if [ -s /tmp/combined_sys_alerts.txt ]; then
    alert_body=$(cat /tmp/combined_sys_alerts.txt)
    send_alert "$alert_body"
    # Clear the temporary file
    > /tmp/combined_sys_alerts.txt
else
    echo "✅ INFO: No alerts to send."
fi


echo -e "\n==== End of Report ====" | tee -a "$LOGFILE"
