# ---- http/https file server (lighttpd): paste into /mnt/sdcard/lp_app.sh ----
# Place this block right AFTER the line that remounts the card read-write
#   mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
# and BEFORE "/tmp/sync_loop.sh" (which never returns). lighttpd serves files
# from /mnt/sdcard, so it must start after the final mount, not before the
# umount like sshd. It daemonizes itself, logs to /tmp, and keeps only the
# files being served open on the card.
if [ -f /mnt/sdcard/bin/start-httpd.sh ]; then
  sh /mnt/sdcard/bin/start-httpd.sh || echo "start-httpd.sh failed, see /mnt/sdcard/logs/httpd.log"
fi
# ---- end http/https file server ----
