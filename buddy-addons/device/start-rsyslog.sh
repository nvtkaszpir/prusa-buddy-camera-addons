#!/bin/sh
# Start rsyslogd: forward syslog() messages (/dev/log), the kernel log and the
# log files on the card to a remote syslog server. Idempotent; run on every boot.
#
# Usage: sh start-rsyslog.sh [restart|stop]
#   (no argument)  install/refresh files, start if not running, restart if the
#                  bundle or the config changed on the card. If the camera is not
#                  ready (see "Readiness"), start a waiter and return at once
#   restart        same, but always restart a running rsyslogd
#   stop           stop a running rsyslogd and the waiter, then exit
#   wait           internal: the waiter, started by the no-argument call
#
# Layout:
#   /mnt/sdcard/bin/rsyslog/          bundle from out/rsyslog/ (flat directory)
#   /mnt/sdcard/bin/rsyslog.conf      config; REMOTE_HOST must be replaced
#   /userdata/rsyslog/bundle/         copy of the bundle: rsyslogd, modules, libs and
#                                     musl's loader ld-musl-armhf.so.1
#   /userdata/rsyslog/rsyslog.conf    copy of the config (card wins, if it passes checks)
#   /userdata/rsyslog/work/           rsyslog workDirectory (imfile read offsets); state
#                                     files for inodes no longer in /mnt/sdcard/logs are
#                                     removed before each start
#   /tmp/rsyslogd.pid, /tmp/rsyslogd.log   pid file and rsyslogd's startup output
#   /tmp/rsyslog-wait.pid             pid of the waiter, while the camera is not ready
#   /mnt/sdcard/bin/ntpsync           clock check of the readiness gate (exit 0 = synchronized)
#
# rsyslogd is a dynamic musl program (its modules are loaded with dlopen,
# which a static binary cannot do). It is started through its own loader:
#   bundle/ld-musl-armhf.so.1 --library-path bundle bundle/rsyslogd -M bundle ...
# so it never uses the camera's uClibc.
#
# The microSD card (/mnt/sdcard/bin) is the source of truth. A changed bundle
# file is copied when its md5 differs; files no longer on the card are removed.
# A new config is installed only if it no longer names REMOTE_HOST and passes
# "rsyslogd -N1"; otherwise it is logged and ignored, and a running rsyslogd
# keeps its old config.
#
# Readiness: rsyslogd starts only when wlan0 has an IPv4 station address (not the AP
# address), hostapd is not running, and NTP has synchronized the clock (ntpsync exits
# 0). Otherwise a waiter polls every 10 s and logs state changes only. A running
# rsyslogd is left alone while the camera is not ready.
#
# The stock ntpd (S10ntp) starts seconds after boot, before Wi-Fi has an address, and stays
# unsynchronized for many minutes (why was not traced; failed DNS lookups retried at growing
# intervals is a guess). The waiter therefore restarts ntpd at the first poll that
# sees a station address but an unsynchronized clock, and again every 30 s while the clock
# stays unsynchronized (at most NTPD_RESTARTS times): a restart right after Wi-Fi comes up
# does not always help, although /etc/resolv.conf already lists the DNS servers (seen at boot:
# one restart at 26 s, synchronized only at 335 s; with retries, a restart at 88 s synchronized
# within 11 s). Same command line as the running ntpd (lp_app may run its own, with
# -c /tmp/ntp.conf). If no ntpd runs, none is started.
#
# lp_app's own syslog forwarding is disabled on every start (also before the readiness
# gate, as lp_app reads its settings once when it starts, right after this script):
#   /mnt/sdcard/syslog_srv        renamed to syslog_srv.disabled (an older one is replaced)
#   /mnt/sdcard/srv_cfg.txt       SYSLOG_IP= and SYSLOG_PORT= lines (lp_app 3.1.7+) are
#                                 commented out with "# disabled by start-rsyslog.sh: ";
#                                 the other lines are left as they are
# rsyslog already forwards lp_app's log files; with both, every line arrives twice.

SRC=/mnt/sdcard/bin
DIR=/userdata/rsyslog
BUNDLE=$DIR/bundle
CONF=$DIR/rsyslog.conf
WORK=$DIR/work
PIDFILE=/tmp/rsyslogd.pid
SRVLOG=/tmp/rsyslogd.log
PLACEHOLDER=REMOTE_HOST
# Directory tailed by imfile in rsyslog.conf (for the state file cleanup).
LOGDIR=/mnt/sdcard/logs
WAITPID=/tmp/rsyslog-wait.pid
WAIT_INTERVAL=10
# ntpd restarts by the waiter while the clock stays unsynchronized: every 3 polls (30 s), at most 10.
NTPD_RESTART_POLLS=3
NTPD_RESTARTS=10
# Readiness gate inputs. The overrides in the environment are for testing only.
IFCONFIG=${IFCONFIG:-ifconfig}
WIFI_IF=${WIFI_IF:-wlan0}
AP_IP=${AP_IP:-192.168.42.1}
NTPSYNC=${NTPSYNC:-/mnt/sdcard/bin/ntpsync}
# ntpd restarted once by the waiter; the program used when argv[0] is not in PATH.
NTPD_PIDFILE=/var/run/ntpd.pid
NTPD_BIN=/oem/usr/bin/ntpd
# lp_app's built-in syslog forwarding settings.
LP_SYSLOG_SRV=/mnt/sdcard/syslog_srv
LP_SRV_CFG=/mnt/sdcard/srv_cfg.txt
LP_SYSLOG_RE='^[[:space:]]*SYSLOG_(IP|PORT)[[:space:]]*='
LP_DISABLED_PREFIX='# disabled by start-rsyslog.sh: '
# This script's absolute path: the waiter runs with cwd /.
case "$0" in /*) self=$0 ;; *) self=$(pwd)/$0 ;; esac

if [ -d "$LOGDIR" ]; then LOG=$LOGDIR/rsyslog.log; else LOG=/tmp/rsyslog.log; fi
log() { echo "start-rsyslog: $*" >> "$LOG"; }
md5() { md5sum < "$1" | cut -d' ' -f1; }

# rsyslogd through the bundled musl loader; arguments are passed on.
run_rsyslogd() {
  "$BUNDLE/ld-musl-armhf.so.1" --library-path "$BUNDLE" "$BUNDLE/rsyslogd" -M "$BUNDLE" "$@"
}

# Running rsyslogd pid on stdout; fails if none.
running_pid() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -q rsyslogd "/proc/$pid/cmdline" 2>/dev/null || return 1
  echo "$pid"
}

stop_server() {
  pid=$(running_pid) || { rm -f "$PIDFILE"; return 0; }
  kill "$pid" 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
    [ "$i" = 5 ] && kill -9 "$pid" 2>/dev/null
  done
  rm -f "$PIDFILE"
  log "stopped rsyslogd (pid $pid)"
}

# Non-comment line naming the placeholder target?
has_placeholder() { grep -q "^[^#]*$PLACEHOLDER" "$1"; }

# Why the camera is not ready for forwarding, on stdout; nothing when it is ready.
not_ready_reason() {
  ip=$("$IFCONFIG" "$WIFI_IF" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -n 1)
  if [ -z "$ip" ]; then echo "no station address on $WIFI_IF"; return 0; fi
  if [ "$ip" = "$AP_IP" ]; then echo "$WIFI_IF has the AP address $AP_IP"; return 0; fi
  if pidof hostapd >/dev/null 2>&1; then echo "hostapd is running"; return 0; fi
  out=$("$NTPSYNC" 2>&1); rc=$?
  case $rc in
    0) ;;
    1) echo "NTP not synchronized" ;;
    *) echo "ntpsync failed (rc $rc): $out" ;;
  esac
}

# Running ntpd pid on stdout; fails if none. Pid file first, then a /proc scan.
ntpd_pid() {
  pid=$(cat "$NTPD_PIDFILE" 2>/dev/null)
  if [ -n "$pid" ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = ntpd ]; then
    echo "$pid"
    return 0
  fi
  for d in /proc/[0-9]*; do
    if [ "$(cat "$d/comm" 2>/dev/null)" = ntpd ]; then
      echo "${d#/proc/}"
      return 0
    fi
  done
  return 1
}

# Restart the running ntpd with its own command line (it started before the network
# and keeps retrying DNS). Does nothing but log when no ntpd is running.
restart_ntpd() {
  if ! pid=$(ntpd_pid); then
    log "ntpd not running, not restarting it"
    return 1
  fi
  # argv, one per line (arguments with newlines do not occur in ntpd command lines).
  args=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null)
  if [ -z "$args" ]; then
    log "failed to restart ntpd: cannot read /proc/$pid/cmdline"
    return 1
  fi
  oldifs=$IFS
  IFS='
'
  set -f
  set -- $args
  set +f
  IFS=$oldifs
  prog=$1
  shift
  case "$prog" in
    */*) ;;
    *) command -v "$prog" >/dev/null 2>&1 || prog=$NTPD_BIN ;;
  esac
  ntpd_pidfile=""
  prev=""
  for a in "$@"; do
    [ "$prev" = -p ] && ntpd_pidfile=$a
    prev=$a
  done
  kill "$pid" 2>/dev/null
  for i in 1 2 3 4 5; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  [ -n "$ntpd_pidfile" ] && rm -f "$ntpd_pidfile"
  # ntpd daemonizes itself; the parent returns at once.
  if (cd / && exec "$prog" "$@") < /dev/null > /dev/null 2>&1; then
    # The nameserver count shows whether DNS was configured yet (udhcpc writes /etc/resolv.conf).
    log "restarted ntpd ($(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null) nameserver(s) in /etc/resolv.conf): $prog $*"
  else
    log "failed to restart ntpd (rc $?): $prog $*"
    return 1
  fi
}

# Pid of the running waiter on stdout; fails if none.
waiter_pid() {
  [ -f "$WAITPID" ] || return 1
  pid=$(cat "$WAITPID" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -q start-rsyslog "/proc/$pid/cmdline" 2>/dev/null || return 1
  echo "$pid"
}

# Start the waiter detached, the way start-sshd.sh starts dropbear. Returns at once.
start_waiter() {
  waiter_pid >/dev/null && return 0
  cp "$self" /tmp/rsyslog-wait.sh || return 1
  (cd / && exec sh /tmp/rsyslog-wait.sh wait </dev/null >>/tmp/rsyslog-wait.out 2>&1) &
  echo $! > "$WAITPID"
}

stop_waiter() {
  pid=$(waiter_pid) || { rm -f "$WAITPID"; return 0; }
  kill "$pid" 2>/dev/null
  rm -f "$WAITPID"
  log "stopped waiter (pid $pid)"
}

# Waiter: poll until ready. Logs state changes only, never every poll. While there is a
# station address but the clock is unsynchronized, restart ntpd at once and then every
# NTPD_RESTART_POLLS polls, at most NTPD_RESTARTS times per run.
wait_for_ready() {
  last=""
  ntpd_restarts=0
  polls_since_restart=$NTPD_RESTART_POLLS
  while :; do
    reason=$(not_ready_reason)
    if [ -z "$reason" ]; then
      log "ready, starting rsyslogd"
      return 0
    fi
    if [ "$reason" != "$last" ]; then
      log "waiting: $reason"
      last=$reason
    fi
    if [ "$reason" = "NTP not synchronized" ]; then
      if [ "$polls_since_restart" -ge "$NTPD_RESTART_POLLS" ] && [ "$ntpd_restarts" -lt "$NTPD_RESTARTS" ]; then
        ntpd_restarts=$((ntpd_restarts + 1))
        polls_since_restart=0
        restart_ntpd
      fi
      polls_since_restart=$((polls_since_restart + 1))
    fi
    sleep "$WAIT_INTERVAL"
  done
}

# Turn off lp_app's own forwarding so the server does not get its lines twice.
# Idempotent: a renamed file is gone and commented lines no longer match.
disable_builtin_forwarding() {
  if [ -f "$LP_SYSLOG_SRV" ]; then
    if [ -e "$LP_SYSLOG_SRV.disabled" ]; then
      log "replacing $LP_SYSLOG_SRV.disabled with newer $LP_SYSLOG_SRV"
    fi
    if mv -f "$LP_SYSLOG_SRV" "$LP_SYSLOG_SRV.disabled"; then
      log "disabled lp_app syslog forwarding: renamed $LP_SYSLOG_SRV to $LP_SYSLOG_SRV.disabled"
    else
      log "failed to rename $LP_SYSLOG_SRV; lp_app may forward its log too"
    fi
  fi
  # Rewrite only when needed, through a temp file on the card so a power cut
  # never leaves a half-written srv_cfg.txt (lp_app also reads OTA_SRV etc. from it).
  if [ -f "$LP_SRV_CFG" ] && grep -qE "$LP_SYSLOG_RE" "$LP_SRV_CFG"; then
    n=$(grep -cE "$LP_SYSLOG_RE" "$LP_SRV_CFG")
    if sed -r "/$LP_SYSLOG_RE/s/^/$LP_DISABLED_PREFIX/" "$LP_SRV_CFG" > "$LP_SRV_CFG.tmp" &&
       mv -f "$LP_SRV_CFG.tmp" "$LP_SRV_CFG"; then
      log "disabled lp_app syslog forwarding: commented out $n SYSLOG_IP/SYSLOG_PORT line(s) in $LP_SRV_CFG"
    else
      rm -f "$LP_SRV_CFG.tmp"
      log "failed to update $LP_SRV_CFG; lp_app may forward its log too"
    fi
  fi
}

case "$1" in
  stop) stop_waiter; stop_server; exit 0 ;;
  restart) restart=1 ;;
  "") restart=0 ;;
  wait) restart=1; waiter=1 ;;
  *) echo "usage: $0 [restart|stop]" >&2; exit 2 ;;
esac

# Before the readiness gate: lp_app starts right after this script returns, and the
# waiter would be too late. Not in the waiter itself (already done by its parent).
[ "$waiter" = 1 ] || disable_builtin_forwarding

# Readiness gate. The boot hook must not block: when not ready, the waiter runs the
# start path later and this call returns at once.
if [ "$waiter" = 1 ]; then
  wait_for_ready
  rm -f "$WAITPID"
elif [ -n "$(not_ready_reason)" ]; then
  start_waiter
  exit 0
else
  stop_waiter
fi

mkdir -p "$BUNDLE" "$WORK"
chmod 700 "$DIR"

# Refresh the bundle from the card. A running rsyslogd keeps its old
# (replaced) files open, so cp + mv is safe; it is restarted below.
if [ -d "$SRC/rsyslog" ]; then
  for f in "$SRC"/rsyslog/*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    new=$(md5 "$f")
    old=""
    [ -f "$BUNDLE/$name" ] && old=$(md5 "$BUNDLE/$name")
    if [ "$new" != "$old" ]; then
      cp "$f" "$BUNDLE/$name.new" && chmod 755 "$BUNDLE/$name.new" && mv "$BUNDLE/$name.new" "$BUNDLE/$name"
      log "installed rsyslog/$name (md5 $new)"
      restart=1
    fi
  done
  for f in "$BUNDLE"/*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    if [ ! -f "$SRC/rsyslog/$name" ]; then
      rm -f "$f"
      log "removed rsyslog/$name (no longer on the card)"
      restart=1
    fi
  done
fi

if [ ! -x "$BUNDLE/rsyslogd" ] || [ ! -x "$BUNDLE/ld-musl-armhf.so.1" ]; then
  log "no $BUNDLE/rsyslogd or $BUNDLE/ld-musl-armhf.so.1 (copy out/rsyslog/ to $SRC/rsyslog/), cannot start rsyslogd"
  exit 1
fi

# musl ignores the camera's /etc/TZ (uClibc's POSIX TZ string file), so pass
# it on; otherwise forwarded timestamps are always UTC.
if [ -z "$TZ" ] && [ -r /etc/TZ ]; then
  TZ=$(cat /etc/TZ)
  export TZ
fi

# Refresh the config from the card (card wins), but only if the remote target
# was filled in and "rsyslogd -N1" accepts it; otherwise keep the installed one.
conf_bad=0
if [ -f "$SRC/rsyslog.conf" ]; then
  new=$(md5 "$SRC/rsyslog.conf")
  old=""
  [ -f "$CONF" ] && old=$(md5 "$CONF")
  if [ "$new" != "$old" ]; then
    if has_placeholder "$SRC/rsyslog.conf"; then
      log "REJECTED $SRC/rsyslog.conf (md5 $new): replace $PLACEHOLDER with your syslog server first"
      conf_bad=1
    else
      cp "$SRC/rsyslog.conf" "$CONF.new"
      if out=$(cd / && run_rsyslogd -N1 -f "$CONF.new" 2>&1 < /dev/null); then
        mv "$CONF.new" "$CONF"
        log "installed rsyslog.conf (md5 $new)"
        restart=1
      else
        rm -f "$CONF.new"
        log "REJECTED $SRC/rsyslog.conf (md5 $new), keeping the installed config. rsyslogd -N1 said:"
        echo "$out" >> "$LOG"
        conf_bad=1
      fi
    fi
  fi
fi

if [ ! -f "$CONF" ]; then
  log "no $CONF (copy device/rsyslog.conf to $SRC/rsyslog.conf and set the target), not starting rsyslogd"
  exit 1
fi
if has_placeholder "$CONF"; then
  log "$CONF still names $PLACEHOLDER, not starting rsyslogd"
  exit 1
fi

# Check the installed config (with a possibly new bundle) before touching a
# running rsyslogd.
if ! out=$(cd / && run_rsyslogd -N1 -f "$CONF" 2>&1 < /dev/null); then
  log "config check of $CONF failed, not (re)starting. rsyslogd -N1 said:"
  echo "$out" >> "$LOG"
  exit 1
fi

if pid=$(running_pid); then
  if [ "$restart" = 1 ]; then
    stop_server
  else
    log "already running (pid $pid)"
    exit "$conf_bad"
  fi
fi

# imfile names its state files "imfile-state:<inode>[:<content hash>]". vfat
# hands out new inode numbers on every mount, so state files for inodes that
# no file in $LOGDIR has now can never be used again; drop them (rsyslogd is
# not running here, so it owns none of them).
if [ -d "$LOGDIR" ]; then
  inodes=" $(ls -1i "$LOGDIR" 2>/dev/null | while read -r ino name; do printf '%s ' "$ino"; done)"
  n=0
  for f in "$WORK"/imfile-state:*; do
    [ -f "$f" ] || continue
    ino=${f##*/imfile-state:}
    ino=${ino%%:*}
    case "$inodes" in
      *" $ino "*) ;;
      *) rm -f "$f"; n=$((n + 1)) ;;
    esac
  done
  [ "$n" = 0 ] || log "removed $n stale imfile state file(s)"
fi

# rsyslogd daemonizes itself and writes $PIDFILE; the parent returns once the
# daemon is up. cwd / and startup output in /tmp. Of the card it only holds
# open the log files imfile is tailing.
rm -f "$PIDFILE"
if (cd / && run_rsyslogd -f "$CONF" -i "$PIDFILE") < /dev/null >> "$SRVLOG" 2>&1; then
  i=0
  while ! pid=$(running_pid) && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
  done
fi
if pid=$(running_pid); then
  log "started rsyslogd (pid $pid)"
else
  log "rsyslogd failed to start, see $SRVLOG"
  exit 1
fi
exit "$conf_bad"
