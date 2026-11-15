# ---- syslog forwarder (rsyslog): paste into /mnt/sdcard/lp_app.sh ----
# Place this block AFTER the line that remounts the card read-write
#   mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
#   (or right after the microSD check block, fsck-hook.sh, which replaces that line)
# and after the http/https file server block (if you have it), right BEFORE
# "/tmp/sync_loop.sh" (which never returns). rsyslogd reads its config from the
# card and keeps the lp_app log files in /mnt/sdcard/logs open while tailing
# them, so it must start after the final mount, not before the umount like
# sshd. Started before sync_loop.sh, so /dev/log exists before lp_app runs.
# rsyslogd daemonizes itself and writes its startup output to
# /tmp/rsyslogd.log; sync_loop.sh killing lp_app does not stop it.
# start-rsyslog.sh returns at once; if the camera is not ready yet, rsyslogd starts later (see the script).
if [ -f /mnt/sdcard/bin/start-rsyslog.sh ]; then
  sh /mnt/sdcard/bin/start-rsyslog.sh || echo "start-rsyslog.sh failed, see /mnt/sdcard/logs/rsyslog.log"
fi
# ---- end syslog forwarder ----
