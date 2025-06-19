# Sysmonitor - User Login & Activity Audit Script

This Bash script monitors user logins, SSH login failures, and recent shell activity. It sends email alerts for failed login attempts and logs relevant information for audit and security purposes.

## Requirements

- Bash shell
- `mail` command (from `mailutils` or similar)
- Root or sudo privileges

## Configuration

Create a config file at `/etc/sysmonitor.conf` with the following variable:

```bash
ALERT_EMAIL="you@example.com"
````

This email will receive security alerts.

## Permissions & Security

* Only root or trusted administrators should run this script.
* Set secure permissions:

```bash
chmod 700 /path/to/sysmonitor.sh
chown root:root /path/to/sysmonitor.sh
```

* Secure output logs:

```bash
# Alert logs
touch /var/log/sysmonitor_alerts.log
chmod 600 /var/log/sysmonitor_alerts.log

# Optional: script runtime output
/path/to/sysmonitor.sh >> /var/log/sysmonitor.log 2>&1
chmod 600 /var/log/sysmonitor.log
```

## Usage

Run manually:

```bash
sudo /path/to/sysmonitor.sh
```

Or schedule via cron for hourly/daily monitoring.

## Alert Example

When failed SSH logins are detected, you’ll receive an email with:

* Count of failed logins in the past hour
* Source IP summary
* Recent attempt timestamps and IPs

##  Notes

* This script uses system logs (`journalctl` and `last`) and user history files.
* Make sure user shell histories (`.bash_history`, `.zsh_history`) are readable by root.

## File Structure

```
/etc/sysmonitor.conf       # Config file (with ALERT_EMAIL)
/path/to/sysmonitor.sh     # Script itself
/var/log/sysmonitor_alerts.log   # Alert log
/var/log/sysmonitor_mail_errors.log  # Mail error log
```