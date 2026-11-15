#!/bin/sh
# Remove the add-ons from the camera. Run as root on the camera: over ssh (task buddy:uninstall)
# or once from a one-shot boot hook on the microSD card. See docs/install/uninstall.md.
#
# Usage: sh uninstall.sh [-n] [--stock] [--hosts]
#   (no option)  stop the add-on daemons and loops, undo the /etc/passwd bind mount, delete the add-on
#                state in /userdata (bin, ssh, httpd, rsyslog, logrotate) and the add-on files in
#                /mnt/sdcard/bin. The hook blocks in /mnt/sdcard/lp_app.sh then do nothing on the next boot.
#   --stock      also rename /mnt/sdcard/lp_app.sh to lp_app.sh.bak-uninstall-<time>, so the next boot starts
#                lp_app the stock way; set rtsp_server_mode back to the factory default 1 (RTSP off); delete
#                /mnt/sdcard/userdata/, the hook's copies of /userdata (Prusa Connect token, Wi-Fi password);
#                delete /oem/.ash_history, which interactive telnet/ssh shells write (HOME=/oem)
#   --hosts      also delete the connect-ota.prusa3d.com line from /etc/hosts (remounts the rootfs rw)
#   -n           dry run: print what would be done and change nothing
#
# It does not reboot. task buddy:uninstall runs safe-reboot.sh afterwards, which unmounts the card cleanly.
#
# Only the dropbear listener is stopped, never the session processes, and that last: the ssh session
# that runs this script keeps working. HUP and PIPE are ignored, so a dropped session does not stop the
# script half-way.
#
# The paths can be overridden from the environment, for a test run on a PC against a scratch tree:
#   USERDATA=/tmp/t/userdata SDCARD=/tmp/t/sdcard RUNDIR=/tmp/t/run PASSWD=/tmp/t/passwd \
#   HOSTS_FILE=/tmp/t/hosts OEM_HISTORY=/tmp/t/ash_history sh uninstall.sh --stock --hosts

USERDATA="${USERDATA:-/userdata}"
SDCARD="${SDCARD:-/mnt/sdcard}"
RUNDIR="${RUNDIR:-/tmp}"
PASSWD="${PASSWD:-/etc/passwd}"
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
OEM_HISTORY="${OEM_HISTORY:-/oem/.ash_history}"
OTA_HOST=connect-ota.prusa3d.com
OTA_RE='[[:space:]]connect-ota\.prusa3d\.com([[:space:]]|$)'

# Add-on state on the flash. The start scripts (or a manual install) create these; the firmware does not.
USERDATA_DIRS="bin ssh httpd rsyslog logrotate"
# Add-on files in $SDCARD/bin, as copied by docs/install/3-installation.md and task buddy:sync.
CARD_FILES="dropbearmulti rsync drill authorized_keys start-sshd.sh
lighttpd mbedtls-gen-key mbedtls-cert-write start-httpd.sh lighttpd.conf dirlisting-header.html htpasswd
fsck.fat sdcard-fsck.sh
rsyslog rsyslog.conf start-rsyslog.sh ntpsync
logrotate logrotate.conf start-logrotate.sh
sshd-hook.sh httpd-hook.sh fsck-hook.sh rsyslog-hook.sh logrotate-hook.sh
uninstall.sh safe-reboot.sh timelapse-clean.sh"
# Command line substrings of the add-on processes other than dropbear: rsyslogd (started through the
# bundled loader), the rsyslog waiter, the logrotate loop, lighttpd and its reverse-DNS title job.
# No spaces inside a pattern: the list is split on whitespace.
PROC_PATTERNS="$USERDATA/rsyslog/bundle/
$RUNDIR/rsyslog-wait.sh
$RUNDIR/logrotate-loop.sh
$USERDATA/bin/lighttpd
$SDCARD/bin/start-httpd.sh"

DRY=0
STOCK=0
HOSTS=0
for arg in "$@"; do
  case "$arg" in
    -n) DRY=1 ;;
    --stock) STOCK=1 ;;
    --hosts) HOSTS=1 ;;
    *) echo "usage: $0 [-n] [--stock] [--hosts]" >&2; exit 2 ;;
  esac
done

trap '' HUP PIPE

LOGFILE=""
[ "$DRY" = 0 ] && [ -d "$SDCARD/logs" ] && LOGFILE="$SDCARD/logs/uninstall.log"
log() {
  echo "uninstall: $*"
  [ -z "$LOGFILE" ] || echo "$(date '+%Y-%m-%d %H:%M:%S') uninstall: $*" >> "$LOGFILE"
}
[ "$DRY" = 0 ] || log "dry run, nothing is changed"

failed=0

# act DESCRIPTION CMD...: run CMD and log the outcome; in a dry run only log DESCRIPTION.
act() {
  desc=$1
  shift
  if [ "$DRY" = 1 ]; then
    log "would $desc"
  elif "$@"; then
    log "$desc: ok"
  else
    log "FAILED to $desc"
    failed=1
  fi
}

# stop_pid PID WHAT: SIGTERM, then SIGKILL after 5 s.
stop_pid() {
  if [ "$DRY" = 1 ]; then
    log "would stop $2 (pid $1)"
    return 0
  fi
  kill "$1" 2>/dev/null
  i=0
  while kill -0 "$1" 2>/dev/null && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
    [ "$i" = 5 ] && kill -9 "$1" 2>/dev/null
  done
  if kill -0 "$1" 2>/dev/null; then
    log "FAILED to stop $2 (pid $1)"
    failed=1
  else
    log "stopped $2 (pid $1)"
  fi
}

# ---- processes (the dropbear listener comes last, at the end) ------------------------------------
# Scan /proc instead of trusting the pid files: they can be stale or missing.
for pattern in $PROC_PATTERNS; do
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    cmd=$(tr '\0' ' ' 2>/dev/null < "$d/cmdline") || continue
    cmd=${cmd% }
    case "$cmd" in
      *"$pattern"*) stop_pid "$pid" "$cmd" ;;
    esac
  done
done

# ---- /etc/passwd bind mount (start-sshd.sh) ------------------------------------------------------
if grep -q " $PASSWD " /proc/mounts 2>/dev/null; then
  act "unmount the bind mount on $PASSWD" umount "$PASSWD"
fi

# ---- /userdata ----------------------------------------------------------------------------------
for d in $USERDATA_DIRS; do
  [ -e "$USERDATA/$d" ] || continue
  act "delete $USERDATA/$d" rm -rf "$USERDATA/$d"
done

# ---- microSD card: add-on files, so the hook blocks find no start script -------------------------
for f in $CARD_FILES; do
  [ -e "$SDCARD/bin/$f" ] || continue
  act "delete $SDCARD/bin/$f" rm -rf "$SDCARD/bin/$f"
done
# busybox on the camera has no rmdir.
if [ "$DRY" = 0 ] && [ -d "$SDCARD/bin" ]; then
  if [ -z "$(ls -A "$SDCARD/bin")" ]; then
    act "delete the empty $SDCARD/bin" rm -r "$SDCARD/bin"
  else
    log "keeping $SDCARD/bin, it holds other files: $(ls -A "$SDCARD/bin" | tr '\n' ' ')"
  fi
fi

# ---- --stock: no hook, factory RTSP setting, no config copies on the card ------------------------
if [ "$STOCK" = 1 ]; then
  if [ -f "$SDCARD/lp_app.sh" ]; then
    bak="$SDCARD/lp_app.sh.bak-uninstall-$(date +%Y%m%d%H%M%S)"
    act "rename $SDCARD/lp_app.sh to $bak" mv "$SDCARD/lp_app.sh" "$bak"
  fi
  if grep -q '^rtsp_server_mode=' "$USERDATA/xhr_config.ini" 2>/dev/null &&
    ! grep -q '^rtsp_server_mode=1$' "$USERDATA/xhr_config.ini"; then
    act "set rtsp_server_mode=1 (RTSP off) in $USERDATA/xhr_config.ini" \
      sed -i 's/^rtsp_server_mode=.*/rtsp_server_mode=1/' "$USERDATA/xhr_config.ini"
  fi
  if [ -e "$SDCARD/userdata" ]; then
    act "delete $SDCARD/userdata (copies of $USERDATA)" rm -rf "$SDCARD/userdata"
  fi
  if [ -e "$OEM_HISTORY" ]; then
    act "delete $OEM_HISTORY (shell history on the firmware's oem partition)" rm -f "$OEM_HISTORY"
  fi
fi

# ---- --hosts: unblock the OTA host ---------------------------------------------------------------
# Rewrites the file in place (cat >), so its owner and mode stay as they are.
strip_ota_host() {
  grep -v -E "$OTA_RE" "$HOSTS_FILE" > "$RUNDIR/hosts.uninstall" &&
    cat "$RUNDIR/hosts.uninstall" > "$HOSTS_FILE"
  rc=$?
  rm -f "$RUNDIR/hosts.uninstall"
  return "$rc"
}
if [ "$HOSTS" = 1 ] && grep -q -E "$OTA_RE" "$HOSTS_FILE" 2>/dev/null; then
  if [ "$DRY" = 1 ] || [ -w "$HOSTS_FILE" ]; then
    act "delete the $OTA_HOST line from $HOSTS_FILE" strip_ota_host
  elif mount -o remount,rw /; then
    act "delete the $OTA_HOST line from $HOSTS_FILE" strip_ota_host
    sync
    mount -o remount,ro / || log "WARNING: could not remount / read-only; RkLunch.sh does it on the next boot"
  else
    log "FAILED to remount / read-write, $HOSTS_FILE unchanged"
    failed=1
  fi
fi

# ---- dropbear listener, last. The session processes are separate and keep running ----------------
if [ -f "$RUNDIR/dropbear.pid" ]; then
  pid=$(cat "$RUNDIR/dropbear.pid" 2>/dev/null)
  if [ -n "$pid" ] && grep -q dropbear "/proc/$pid/cmdline" 2>/dev/null; then
    stop_pid "$pid" "dropbear listener"
  fi
  [ "$DRY" = 1 ] || rm -f "$RUNDIR/dropbear.pid"
fi

if [ "$failed" = 0 ]; then log "done"; else log "done, with failures (see above)"; fi
exit "$failed"
