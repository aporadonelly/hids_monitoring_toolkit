#!/bin/bash

LOGFILE="/home/Testmonitor_alerts.log"
EMAIL_RECIPIENT="nelly.aporado@exocoder.io"
EMAIL_SUBJECT="System Monitoring Alert"
TRACEFILE="/home/monitor_trace.json"

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

# Function to send email alerts
send_alert() {
    local message="$1"
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
    else
        echo "Warning: mail command not found, cannot send alert: $message" | tee -a "$LOGFILE"
    fi
}

# Check for required commands
for cmd in awk bc df free ps ss who last; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found" | tee -a "$LOGFILE"
        exit 1
    fi
done

# Initialize trace file with proper JSON structure if it doesn't exist
# Use a temporary file to avoid race conditions during writes
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
# if [ $(echo "$cpu_usage > 80" | bc) -eq 1 ]; then
if [ $(echo "$cpu_usage < 80" | bc) -eq 1 ]; then
    alert="WARNING: High CPU usage detected: $cpu_usage%"
    echo "$alert" | tee -a "$LOGFILE"
    send_alert "$alert"
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
    send_alert "$alert"
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

# Top 5 Memory-Intensive Processes
echo "Top 5 Memory Intensive Processes:" | tee -a "$LOGFILE"
ps aux --sort=-%mem | awk 'NR>1 {print $0}' | head -n 5 | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

# Disk Usage
disk_usage=$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')
echo "Disk Usage on /: $disk_usage%" | tee -a "$LOGFILE"
if [ "$disk_usage" -gt 80 ]; then
    alert="WARNING: Disk usage above 80%: $disk_usage%"
    echo "$alert" | tee -a "$LOGFILE"
    send_alert "$alert"
fi
echo | tee -a "$LOGFILE"

# Uptime
echo "System Uptime:" | tee -a "$LOGFILE"
uptime -p | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

# Last logged-in users
echo "Last logged in users:" | tee -a "$LOGFILE"
last -n 5 | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

# Current logged-in users
echo "Currently logged-in users:" | tee -a "$LOGFILE"
w | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

# Active network connections (top 10, established)
echo "Active network connections (top 10, established):" | tee -a "$LOGFILE"
ss -tuna state established | head -n 10 | tee -a "$LOGFILE"
echo | tee -a "$LOGFILE"

echo "==== End of Report ====" | tee -a "$LOGFILE"