#!/bin/sh
# Rotate the add-on logs (dropbear, lighttpd, rsyslog): daily, keep 7, no compression.
# See logrotate.conf for how each service reopens or re-reads its file.
# Idempotent; run on every boot.
#
# Usage: sh start-logrotate.sh [run|stop]
#   (no argument)  install/refresh files, start the hourly loop if not running
#   run            rotate now (logrotate's state file makes "daily" mean once per day)
#   stop           stop the hourly loop
#
# Layout:
#   /userdata/bin/logrotate                 from /mnt/sdcard/bin/logrotate (card wins)
#   /userdata/logrotate/logrotate.conf      from /mnt/sdcard/bin/logrotate.conf (card wins)
#   /userdata/logrotate/status              logrotate state file (survives reboot)
#   /tmp/logrotate-loop.sh, .pid, .out      the hourly loop (lost on reboot). It runs from
#                                           /tmp, so the card can be unmounted meanwhile.
#   /mnt/sdcard/logs/logrotate.log          this script's steps and logrotate errors
#                                           (/tmp/logrotate.log without the logs dir)

SRC=/mnt/sdcard/bin
BIN=/userdata/bin
DIR=/userdata/logrotate
CONF=$DIR/logrotate.conf
STATE=$DIR/status
LOOPSH=/tmp/logrotate-loop.sh
PIDFILE=/tmp/logrotate-loop.pid
self="$0"

if [ -d /mnt/sdcard/logs ]; then LOG=/mnt/sdcard/logs/logrotate.log; else LOG=/tmp/logrotate.log; fi
log() { echo "start-logrotate: $*" >> "$LOG"; }
md5() { md5sum < "$1" | cut -d' ' -f1; }

# install_file SRC DST MODE: copy when the content differs (card wins).
install_file() {
  [ -f "$1" ] || return 0
  [ -f "$2" ] && [ "$(md5 "$1")" = "$(md5 "$2")" ] && return 0
  if cp "$1" "$2.new" && mv "$2.new" "$2" && chmod "$3" "$2"; then
    log "installed $2 (md5 $(md5 "$2"))"
  else
    log "failed to install $2"
  fi
}

# Hourly loop pid on stdout; fails if none.
running_pid() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -q logrotate-loop "/proc/$pid/cmdline" 2>/dev/null || return 1
  echo "$pid"
}

rotate_now() {
  if [ ! -x "$BIN/logrotate" ] || [ ! -f "$CONF" ]; then
    log "logrotate or $CONF missing, nothing rotated"
    return 1
  fi
  "$BIN/logrotate" -s "$STATE" "$CONF" >> "$LOG" 2>&1
}

loop() {
  while :; do
    sleep 3600
    # The clock is set by NTP after boot; do not rotate with a 1970 date.
    [ "$(date +%Y)" -ge 2025 ] || continue
    rotate_now
  done
}

start_loop() {
  running_pid >/dev/null && return 0
  cp "$self" "$LOOPSH" || { log "cannot copy $self to $LOOPSH"; return 1; }
  (cd / && exec sh "$LOOPSH" loop) < /dev/null >> /tmp/logrotate-loop.out 2>&1 &
  echo $! > "$PIDFILE"
  log "started hourly loop (pid $!)"
}

stop_loop() {
  pid=$(running_pid) || { rm -f "$PIDFILE"; return 0; }
  kill "$pid" 2>/dev/null
  rm -f "$PIDFILE"
  log "stopped hourly loop (pid $pid)"
}

case "${1:-}" in
  loop) loop ;;
  run) rotate_now ;;
  stop) stop_loop ;;
  "")
    mkdir -p "$BIN" "$DIR"
    install_file "$SRC/logrotate" "$BIN/logrotate" 755
    install_file "$SRC/logrotate.conf" "$CONF" 644
    if [ -x "$BIN/logrotate" ] && [ -f "$CONF" ]; then
      start_loop
    else
      log "logrotate or $CONF missing, loop not started"
    fi
    ;;
  *) echo "usage: $0 [run|stop]" >&2; exit 2 ;;
esac
