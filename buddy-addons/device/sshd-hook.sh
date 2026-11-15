# ---- ssh server (dropbear + rsync): paste into /mnt/sdcard/lp_app.sh ----
# Place this block right BEFORE the line "umount /mnt/sdcard" (in the
# sdcard/, sdcard_rsync/ and sdcard_no_rsync/ hook variants), or right before
# the final "lp_app --noshell ..." line (in the 8/ variant). It must run while
# the card is still mounted at /mnt/sdcard. Dropbear is a separate daemon that
# keeps nothing open on the card, so the umount/remount still works, and
# sync_loop.sh killing lp_app does not stop sshd.
if [ -f /mnt/sdcard/bin/start-sshd.sh ]; then
  sh /mnt/sdcard/bin/start-sshd.sh || echo "start-sshd.sh failed, see /mnt/sdcard/logs/dropbear.log"
fi
# ---- end ssh server ----
