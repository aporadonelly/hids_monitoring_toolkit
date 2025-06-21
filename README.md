# Linux System Monitoring Toolkit

## Overview

This Bash-based toolkit monitors key system metrics on a Linux machine and detects suspicious activity. It collects CPU, memory, disk usage, network connections, user login info, and failed SSH login attempts. Alerts are logged and sent via email for quick response.

---

## Setup Instructions

### 1. Clone or Copy the Script

Place the monitoring script on your Linux system, for example in your home directory:

```bash
/home/yourusername/sysmonitor.sh
```

Make sure the script is executable:

```bash
chmod +x /home/yourusername/sysmonitor.sh
```

---

### 2. Create Required Directories and Log Files

The script writes logs and error files in the following paths by default:

```bash
LOGFILE="/home/Testmonitor_alerts.log"
MAIL_LOG="/var/log/sysmonitor/mail_errors.log"
USER_LOG_FILE="/var/log/auth.log"
TRACEFILE="/home/monitor_trace.json"
```

You need to create the directories and files if they don't exist:

#### Create `/var/log/sysmonitor` directory and mail error log file:

```bash
sudo mkdir -p /var/log/sysmonitor
sudo touch /var/log/sysmonitor/mail_errors.log
```

#### Set ownership and permissions so your user (replace `yourusername`) can write to them:

```bash
sudo chown -R yourusername:yourusername /var/log/sysmonitor
sudo chmod 755 /var/log/sysmonitor
sudo chmod 644 /var/log/sysmonitor/mail_errors.log
```

---

### 3. Permissions for Log Files in Home Directory

Ensure your user owns and has write permission to the home directory log files:

```bash
touch /home/yourusername/Testmonitor_alerts.log
touch /home/yourusername/monitor_trace.json
chown yourusername:yourusername /home/yourusername/Testmonitor_alerts.log /home/yourusername/monitor_trace.json
chmod 644 /home/yourusername/Testmonitor_alerts.log /home/yourusername/monitor_trace.json
```

---

### 4. Verify Required Commands Are Installed

Ensure your system has the required commands used in the script:

```bash
sudo apt-get update
sudo apt-get install -y mailutils jq bc
```

---

### 5. Test the Script

Run the script manually to verify it works:

```bash
/home/yourusername/sysmonitor.sh
```

If it runs without errors, you can set it up as a cron job for periodic monitoring.

---

## Optional: Set Up Cron Job for Automation

To run the monitoring script every 15 minutes, edit your crontab:

```bash
crontab -e
```

Add the line:

```bash
*/15 * * * * /home/yourusername/sysmonitor.sh
```

Save and exit. The script will now run every 15 minutes.

---

## Summary of Important Commands for Setup

```bash
sudo mkdir -p /var/log/sysmonitor
sudo touch /var/log/sysmonitor/mail_errors.log
sudo chown -R yourusername:yourusername /var/log/sysmonitor
sudo chmod 755 /var/log/sysmonitor
sudo chmod 644 /var/log/sysmonitor/mail_errors.log

touch /home/yourusername/Testmonitor_alerts.log /home/yourusername/monitor_trace.json
chown yourusername:yourusername /home/yourusername/Testmonitor_alerts.log /home/yourusername/monitor_trace.json
chmod 644 /home/yourusername/Testmonitor_alerts.log /home/yourusername/monitor_trace.json

sudo apt-get install mailutils jq bc
chmod +x /home/yourusername/sysmonitor.sh
```

---

## Notes

* Replace `yourusername` with your actual Linux username.
* Log files and trace JSON files are kept in your home directory for easier access.
* Mail errors are logged in `/var/log/sysmonitor/mail_errors.log`.
* The script sends combined alerts by email and keeps a detailed log.