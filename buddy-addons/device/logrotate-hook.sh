# ---- log rotation (logrotate): paste into /mnt/sdcard/lp_app.sh ----
# Place this block AFTER the card is mounted read-write (after the mount line, or after the
# syslog forwarder block, rsyslog-hook.sh) and BEFORE "/tmp/sync_loop.sh" (which never returns).
# start-logrotate.sh installs logrotate to /userdata/bin and starts an hourly loop from /tmp.
# The loop survives sync_loop.sh killing lp_app. It needs the card only for the install step.
if [ -f /mnt/sdcard/bin/start-logrotate.sh ]; then
  sh /mnt/sdcard/bin/start-logrotate.sh || echo "start-logrotate.sh failed, see /mnt/sdcard/logs/logrotate.log"
fi
# ---- end log rotation ----
