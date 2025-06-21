#!/bin/bash
# sysmonitor.sh – Enhanced System Monitoring and HIDS Script
# Added: process-level detail, network throughput, user command audit, and cron scheduling hint

#1. CPU and Load Check
# echo "==========CPU and Load Check=========="
load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/,//g')
load_1min=$(echo $load_avg | awk '{print $1}')
cpu_idle=$(top -b -n1 | grep "^%Cpu" | awk '{print $8}')

Thresholds
max_load=0.5      # alert if 1-min load > 0.5 (example for testing)
max_cpu=1         # alert if CPU usage > 1% (example for testing)

# CPU Usage Calculations
if [[ -z "$cpu_idle" ]]; then
  echo "WARNING: Failed to read CPU idle value."
  cpu_usage="N/A"
else
  cpu_usage=$(echo "100 - $cpu_idle" | bc)
fi

# Alerts
if (( $(echo "$load_1min > $max_load" | bc -l) )); then
  echo "ALERT: High load average ($load_1min) – possible CPU overload."
fi

if [[ "$cpu_usage" != "N/A" ]] && (( ${cpu_usage%.*} > max_cpu )); then
  echo "ALERT: High CPU usage (${cpu_usage}% used) – check running processes."
fi


#Top 5 processes by CPU and memory 
echo "INFO: Top 5 memory-intensive processes:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6

# #2. Memory Check
echo "==========Memory Check=========="
eval "$(free -m | awk '/^Mem:/ {printf "total=%s used=%s free=%s available=%d\n", $2, $3, $4, $7 }')"
available=${available:-0}
total=${total:-1} #avoid division of 0

threshold=$(( total / 10 ))

if [ "$available" -lt "$threshold" ]; then
  echo "ALERT: Low available memory (${available} MB of ${total} MB) – possible memory pressure."
else
  echo "Memory available (${available} MB) is within normal threshold."
fi

if [ "$free" -lt 100 ]; then
  echo "WARNING: Very low free memory (${free} MB) – heavy swapping or caching."
fi


# 3. Disk Space and I/O Check
echo "==========Disk Space and I/O Check=========="
df -h --output=source,size,used,avail,pcent,target | grep -vE 'tmpfs|overlay' | tail -n +2 | while read fs size used avail perc mount; do
  perc_val=$(echo "$perc" | tr -d '%')

  # Check if perc_val is a number
  if [[ "$perc_val" =~ ^[0-9]+$ ]]; then
    if [ "$perc_val" -ge 100 ]; then
      echo "ALERT: High disk usage on $mount ($perc used)."
    else 
      echo "Disk usage on $mount is normal ($perc used)."
    fi
  else
    echo "Skipping invalid disk usage value: $perc"
  fi
done

if dmesg | grep -qi "error"; then
  echo "WARNING: Disk or I/O errors found in dmesg output."
fi


# # 4. Network Check
#!/bin/bash

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "$(timestamp) ==========Network Check=========="
current_listening=$(ss -tuln4 | awk '{print $5}' | grep -Eo ':[0-9]+' | sort -u | grep -E '^:[0-9]+$')
expected_ports_array=(22 80 443)

unexpected_found=0
for port in $current_listening; do
  port_num=${port#:}
  if ! [[ " ${expected_ports_array[*]} " =~ " ${port_num} " ]]; then
    echo "$(timestamp) ALERT: Unexpected service listening on port $port."
    sudo ss -tulnp4 | grep ":${port_num} "
    unexpected_found=1
  fi
done

if [ "$unexpected_found" -eq 0 ]; then
  echo "$(timestamp) INFO: No unexpected services listening on non-whitelisted ports."
fi

echo  # blank line for readability

echo "$(timestamp) ==========Established connections and throughput=========="
conn_count=$(ss -tun | grep -c ESTAB)
if [ "$conn_count" -gt 200 ]; then
  echo "$(timestamp) WARNING: High number of network connections ($conn_count ESTABLISHED)."
fi

echo "$(timestamp) INFO: Network traffic summary (bytes received/transmitted on iface):"
awk '/:/ && /eth|ens|wlan/ { gsub(/:/,"",$1); print $1": RX=" $2 " bytes, TX=" $10 " bytes" }' /proc/net/dev

echo "===================================================="
# Alert config
ALERT_LOG="/var/log/sysmonitor_alerts.log"
ALERT_EMAIL="nelly.aporado@exocoder.io"

send_alert() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local alert_msg="$timestamp ALERT: $message"

  # Log alert to file
  echo "$alert_msg" | tee -a "$ALERT_LOG"

  # Send mail and capture output & errors
  echo "$alert_msg" | /usr/bin/mail -s "Sysmonitor Alert" "$ALERT_EMAIL" 2>> /var/log/sysmonitor_mail_errors.log

  local mail_status=$?
  if [ $mail_status -ne 0 ]; then
    echo "$timestamp ERROR: mail command failed with status $mail_status" >> /var/log/sysmonitor_mail_errors.log
  else
    echo "$timestamp INFO: mail sent successfully" >> /var/log/sysmonitor_mail_errors.log
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

# Count failed SSH login attempts
# fail_count=$(journalctl -u ssh --no-pager | grep -c "Failed password")
# if [ "$fail_count" -gt 5 ]; then
#   send_alert "$fail_count failed login attempts detected via SSH."
# else
#   echo "INFO: Failed SSH login attempts: $fail_count"
# fi

# Count failed login attempts in the last 1 hour
fail_log=$(journalctl -u ssh --since "1 hour ago" | grep "Failed password")
fail_count=$(echo "$fail_log" | wc -l)

if [ "$fail_count" -gt 0 ]; then
  echo "ALERT: $fail_count failed SSH login attempts in the last hour."
  
  # Extract and summarize IPs
  ip_summary=$(echo "$fail_log" | awk '{for (i=1; i<=NF; i++) if ($i == "from") print $(i+1)}' | sort | uniq -c)

  # Get recent attempt timestamps
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
getent passwd | while IFS=: read -r username _ uid _ _ _ shell; do
  if [ "$uid" -ge 1000 ] && [[ "$shell" =~ /bash|/sh|/zsh ]]; then
    echo "-- $username --"
    sudo -u "$username" bash -c "tail -n $COMMAND_COUNT ~/.bash_history 2>/dev/null | grep -v -E 'password|secret|key|token' || echo 'No safe history available.'"
    echo
  fi
done



echo "================================================"

# # 6. Suspicious Processes Check
echo "==========Suspicious Processes Check=========="
suspicious=$(ps -eo user,uid,cmd | grep '/tmp' | grep -v grep)
if [ -n "$suspicious" ]; then
  echo "ALERT: Processes running from /tmp (possible malware):"
  echo "$suspicious"
fi

# # 7. Summary
echo "SYSTEM SUMMARY:"
echo "Uptime: $(uptime -p) since $(uptime -s)"
echo "Users logged in: $(who | wc -l); Load(1m): $load_1min; CPU: ${cpu_usage}% used; Mem: ${used}/${total} MB used; Disk(/): $(df -h / | awk 'NR==2 {print $5}') used."
# Cron scheduling hint:
# To run every 5 minutes, add to crontab: */5 * * * * /path/to/sysmonitor.sh >> /var/log/sysmonitor.log 2>&1
