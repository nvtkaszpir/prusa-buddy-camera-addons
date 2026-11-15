# ---- microSD check (fsck.fat): paste into /mnt/sdcard/lp_app.sh ----
# This block REPLACES the two lines
#   umount /mnt/sdcard
#   mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
# i.e. it goes right AFTER the ssh server block (sshd-hook.sh) and right BEFORE
# the http/https file server block (httpd-hook.sh). sdcard-fsck.sh unmounts the
# card, repairs it with fsck.fat -a and mounts it read-write with the same
# options as the original mount line; it runs from /tmp because the card is
# unmounted meanwhile. fsck.fat comes from the card, or from the copy that
# sdcard-fsck.sh keeps in /userdata/bin when the card copy cannot be read.
# If the script is not on the card (or cannot be read), the original two lines
# run, so boot behaves exactly as before.
if cp /mnt/sdcard/bin/sdcard-fsck.sh /tmp/sdcard-fsck.sh 2>/dev/null; then
  rm -f /tmp/fsck.fat
  cp /mnt/sdcard/bin/fsck.fat /tmp/fsck.fat 2>/dev/null || cp /userdata/bin/fsck.fat /tmp/fsck.fat 2>/dev/null
  [ -f /tmp/fsck.fat ] && chmod 755 /tmp/fsck.fat
  (cd / && sh /tmp/sdcard-fsck.sh) || echo "sdcard-fsck.sh failed, see /tmp/sdcard-fsck.log"
else
  umount /mnt/sdcard
  mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
fi
# ---- end microSD check ----
