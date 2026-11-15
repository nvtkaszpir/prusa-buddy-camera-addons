#!/bin/sh
# Check and repair the microSD vfat filesystem at boot, then mount it read-write.
#
# Replaces the plain "umount /mnt/sdcard" + "mount -t vfat ..." pair of the boot
# hook (see fsck-hook.sh). Must run from /tmp (the hook copies it there), never
# from the card: the card is unmounted while fsck.fat runs.
#
# Flow:
#   1. log the pre-state of the card (mounted?, ro/rw, does a test write work)
#   2. refresh the persistent fallback $PERSIST_DIR/fsck.fat from the card
#   3. sync, umount (retried); if the card stays mounted: no fsck, try
#      "mount -o remount,rw", exit 1
#   4. fsck.fat -a -w (automatic repair) under timeout $FSCK_TIMEOUT
#   5. mount -t vfat -o $MOUNT_OPTS, verify a test write; if read-only or the
#      write fails, "mount -o remount,rw" once
#   6. append the /tmp log to $SDCARD_MNT/logs/fsck.log
# Exit status: 0 only if the card ends up mounted read-write and writable.
# fsck.fat exit codes (dosfstools 4.2 man page): 0 = no errors, 1 = errors found and corrected, or an internal
# error (a fatal error such as an unreadable device also exits 1, so read the log), 2 = usage error, filesystem
# not accessed. 124/143 = killed by timeout, 137 = killed (OOM).
#
# Every setting can be overridden from the environment, e.g. for a test run on
# a PC against a loop-mounted image:
#   SDCARD_DEV=/dev/loop0 SDCARD_MNT=/mnt/test FSCK=/usr/sbin/fsck.fat \
#   PERSIST_DIR= LOG=/tmp/test-fsck.log sh sdcard-fsck.sh

SDCARD_MNT="${SDCARD_MNT:-/mnt/sdcard}"
MOUNT_OPTS="${MOUNT_OPTS:-rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro}"
FSCK_TIMEOUT="${FSCK_TIMEOUT:-600}"
LOG="${LOG:-/tmp/sdcard-fsck.log}"
# Directory for the persistent fallback copy of fsck.fat; empty disables it.
PERSIST_DIR="${PERSIST_DIR-/userdata/bin}"

# Print field N (1=device, 4=options) of the last /proc/mounts entry for $SDCARD_MNT.
mount_field() {
  _f=""
  while read -r _dev _mnt _type _opts _rest; do
    if [ "$_mnt" = "$SDCARD_MNT" ]; then
      case "$1" in
        1) _f="$_dev" ;;
        4) _f="$_opts" ;;
      esac
    fi
  done < /proc/mounts
  echo "$_f"
}

is_mounted() { [ -n "$(mount_field 1)" ]; }

# Is $SDCARD_DEV mounted anywhere (not only at $SDCARD_MNT)?
dev_mounted() {
  while read -r _dev _rest; do
    [ "$_dev" = "$SDCARD_DEV" ] && return 0
  done < /proc/mounts
  return 1
}

mount_mode() {
  case ",$(mount_field 4)," in
    *,ro,*) echo ro ;;
    *,rw,*) echo rw ;;
    *) echo "?" ;;
  esac
}

write_ok() {
  _t="$SDCARD_MNT/.sdcard-fsck-test.$$"
  if (: > "$_t") 2>/dev/null; then
    rm -f "$_t"
    return 0
  fi
  return 1
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') sdcard-fsck: $*" >> "$LOG"; }

state() {
  if is_mounted; then
    if write_ok; then w=ok; else w=FAILED; fi
    log "$1: mounted $(mount_field 1) on $SDCARD_MNT, mode $(mount_mode), test write $w"
  else
    log "$1: $SDCARD_MNT not mounted"
  fi
}

# Card mounted rw and writable? Otherwise remount rw once and check again.
ensure_rw() {
  is_mounted || return 1
  if [ "$(mount_mode)" = rw ] && write_ok; then
    return 0
  fi
  log "card is $(mount_mode) or not writable, trying mount -o remount,rw"
  mount -o remount,rw "$SDCARD_MNT" >> "$LOG" 2>&1 || log "remount,rw failed"
  [ "$(mount_mode)" = rw ] && write_ok
}

# Copy the /tmp log onto the card and exit with $1.
finish() {
  if is_mounted && write_ok && mkdir -p "$SDCARD_MNT/logs" 2>/dev/null; then
    cat "$LOG" >> "$SDCARD_MNT/logs/fsck.log"
    sync
  fi
  exit "$1"
}

cd / || exit 1
: > "$LOG"

SDCARD_DEV="${SDCARD_DEV:-$(mount_field 1)}"
SDCARD_DEV="${SDCARD_DEV:-/dev/mmcblk1p1}"
# fsck.fat next to this script (the hook copies it to /tmp), else /tmp/fsck.fat.
if [ -z "$FSCK" ]; then
  FSCK="${0%/*}/fsck.fat"
  [ -f "$FSCK" ] || FSCK=/tmp/fsck.fat
fi

log "start: device $SDCARD_DEV, mount point $SDCARD_MNT, fsck $FSCK"
state "before"

# ---- persistent fallback copy (card still mounted) ---------------------------
# Used by the hook when the card copy cannot be read.
if [ -n "$PERSIST_DIR" ] && [ -f "$SDCARD_MNT/bin/fsck.fat" ]; then
  new=$(md5sum < "$SDCARD_MNT/bin/fsck.fat" | cut -d' ' -f1)
  old=""
  [ -f "$PERSIST_DIR/fsck.fat" ] && old=$(md5sum < "$PERSIST_DIR/fsck.fat" | cut -d' ' -f1)
  if [ "$new" != "$old" ]; then
    if mkdir -p "$PERSIST_DIR" && cp "$SDCARD_MNT/bin/fsck.fat" "$PERSIST_DIR/fsck.fat.new" &&
      mv "$PERSIST_DIR/fsck.fat.new" "$PERSIST_DIR/fsck.fat"; then
      chmod 755 "$PERSIST_DIR/fsck.fat"
      log "installed $PERSIST_DIR/fsck.fat (md5 $new)"
    else
      rm -f "$PERSIST_DIR/fsck.fat.new"
      log "could not copy fsck.fat to $PERSIST_DIR"
    fi
  fi
fi

# ---- umount -------------------------------------------------------------------
sync
n=0
while is_mounted && [ "$n" -lt 5 ]; do
  umount "$SDCARD_MNT" >> "$LOG" 2>&1 && continue
  n=$((n + 1))
  log "umount attempt $n failed"
  sleep 1
done

if is_mounted || dev_mounted; then
  log "card still mounted, NOT running fsck.fat on a mounted filesystem"
  ensure_rw || log "card is not writable"
  state "after"
  finish 1
fi

# ---- fsck ---------------------------------------------------------------------
if [ -x "$FSCK" ]; then
  # busybox timeout is "timeout -t SECS PROG" in older and "timeout SECS PROG"
  # in newer versions; no timeout at all if the applet is missing.
  if ! command -v timeout > /dev/null 2>&1; then
    set --
  elif timeout -t 1 true > /dev/null 2>&1; then
    set -- timeout -t "$FSCK_TIMEOUT"
  else
    set -- timeout "$FSCK_TIMEOUT"
  fi
  log "running: $* $FSCK -a -w $SDCARD_DEV"
  "$@" "$FSCK" -a -w "$SDCARD_DEV" >> "$LOG" 2>&1
  rc=$?
  case "$rc" in
    0) log "fsck.fat exit 0: filesystem clean" ;;
    1) log "fsck.fat exit 1: errors corrected (or fatal error, see output above)" ;;
    2) log "fsck.fat exit 2: usage error, filesystem not accessed" ;;
    124 | 143) log "fsck.fat exit $rc: killed by timeout after ${FSCK_TIMEOUT}s, repair may be incomplete" ;;
    137) log "fsck.fat exit 137: killed (out of memory?), repair may be incomplete" ;;
    *) log "fsck.fat exit $rc: filesystem NOT repaired" ;;
  esac
else
  log "no executable fsck.fat at $FSCK, skipping fsck"
fi

# ---- mount --------------------------------------------------------------------
if ! mount -t vfat -o "$MOUNT_OPTS" "$SDCARD_DEV" "$SDCARD_MNT" >> "$LOG" 2>&1; then
  log "mount failed, retrying once"
  sleep 1
  if ! mount -t vfat -o "$MOUNT_OPTS" "$SDCARD_DEV" "$SDCARD_MNT" >> "$LOG" 2>&1; then
    # Read-only is better than nothing: the rest of the boot hook copies
    # sync_loop.sh from the card.
    log "mount failed again, trying read-only"
    mount -t vfat -o "$MOUNT_OPTS,ro" "$SDCARD_DEV" "$SDCARD_MNT" >> "$LOG" 2>&1 ||
      log "read-only mount failed too, card is NOT mounted"
  fi
fi

if ensure_rw; then
  state "after"
  log "done: card mounted read-write"
  finish 0
fi
state "after"
log "done: card is NOT mounted read-write"
finish 1
