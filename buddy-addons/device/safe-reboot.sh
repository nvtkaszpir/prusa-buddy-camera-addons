#!/bin/sh
# Reboot the camera with the microSD card cleanly unmounted (FAT dirty bit cleared, nothing half-written).
# Run a copy outside the card, e.g. /tmp/safe-reboot.sh: the card is unmounted while this runs.
# task buddy:reboot copies it to /tmp and runs it over ssh.
#
# Usage: sh safe-reboot.sh [-n]
#   -n  dry run: list what would be stopped, change nothing, no reboot
#
# Why not plain "reboot": it did not restart this camera in testing. "reboot -f" alone skips the unmount,
# and busybox init's own "umount -a -r" would run while lp_app still writes its log to the card. So:
#   1. SIGKILL sync_loop.sh, which would start lp_app again (its TERM trap would also kill -9 lp_app
#      and sleep 300 s);
#   2. SIGTERM lp_app, so it shuts its pipeline down and closes its log file. On firmware 3.1.3 it was still
#      running 20 s later in all three tries (its shutdown joins every service thread) and got SIGKILL. That
#      left no core dump: core_pattern is "core" in lp_app's working directory, the read-only /;
#   3. SIGTERM the add-on processes that use the card or start something that does: rsyslogd and its
#      waiter, lighttpd and its reverse-DNS job, the logrotate loop;
#   4. SIGTERM anything else that still has a file or its working directory on the card;
#   5. sync, umount the card (retried); if it stays busy, remount it read-only;
#   6. after 1 s (so the ssh session that runs this script ends normally first), SIGTERM every dropbear and
#      telnetd process, so the kernel closes their TCP connections with FIN/RST and the clients see the
#      disconnect at once instead of hanging on a peer that is gone; then reboot -f. Detached.
# A process that ignores SIGTERM gets SIGKILL after the wait.

SDCARD="${SDCARD:-/mnt/sdcard}"
DRY=0
case "$1" in
  -n) DRY=1 ;;
  "") ;;
  *) echo "usage: $0 [-n]" >&2; exit 2 ;;
esac

trap '' HUP PIPE
log() { echo "safe-reboot: $*"; }

case "$0" in
  "$SDCARD"/*) log "run a copy outside $SDCARD (e.g. cp $0 /tmp/), the card gets unmounted"; exit 2 ;;
esac
cd / || exit 1
[ "$DRY" = 0 ] || log "dry run, nothing is stopped or unmounted"

# cmdline PID: the command line with spaces, empty for kernel threads and gone processes.
cmdline() {
  c=$(tr '\0' ' ' 2>/dev/null < "/proc/$1/cmdline") || return 1
  echo "${c% }"
}

# pids_by_cmd PATTERN: pids whose command line contains PATTERN.
pids_by_cmd() {
  for d in /proc/[0-9]*; do
    p=${d#/proc/}
    [ "$p" = "$$" ] && continue
    case "$(cmdline "$p")" in *"$1"*) echo "$p" ;; esac
  done
}

# pids_by_argv0 NAME: pids whose program (argv[0] without its directory) is NAME.
pids_by_argv0() {
  for d in /proc/[0-9]*; do
    p=${d#/proc/}
    a=$(cmdline "$p") || continue
    a=${a%% *}
    [ "${a##*/}" = "$1" ] && echo "$p"
  done
}

# pids_on_card: pids with an open file or the working directory on the card.
pids_on_card() {
  for d in /proc/[0-9]*; do
    p=${d#/proc/}
    [ "$p" = "$$" ] && continue
    # ls -l prints "fd/N -> target"; busybox has readlink, but one ls per process is cheaper.
    # shellcheck disable=SC2010
    if ls -l "$d/cwd" "$d/fd" 2>/dev/null | grep -q -e "-> $SDCARD\$" -e "-> $SDCARD/"; then
      echo "$p"
    fi
  done
}

# stop SIGNAL WAIT PID...: send SIGNAL, wait up to WAIT seconds for all, then SIGKILL the rest.
stop() {
  sig=$1
  wait_s=$2
  shift 2
  [ $# -gt 0 ] || return 0
  for p in "$@"; do
    if [ "$DRY" = 1 ]; then
      log "would send SIG$sig to $p: $(cmdline "$p")"
    else
      log "SIG$sig to $p: $(cmdline "$p")"
      kill -"$sig" "$p" 2>/dev/null
    fi
  done
  [ "$DRY" = 1 ] && return 0
  i=0
  while [ "$i" -lt "$wait_s" ]; do
    alive=""
    for p in "$@"; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && return 0
    sleep 1
    i=$((i + 1))
  done
  for p in "$@"; do
    kill -0 "$p" 2>/dev/null || continue
    log "SIGKILL to $p, still running after ${wait_s} s"
    kill -9 "$p" 2>/dev/null
  done
  sleep 1
}

# shellcheck disable=SC2046 # word splitting of pid lists is intended
{
  stop KILL 2 $(pids_by_cmd /tmp/sync_loop.sh)
  stop TERM 20 $(pids_by_argv0 lp_app)
  stop TERM 10 $(pids_by_cmd rsyslog-wait.sh) $(pids_by_cmd logrotate-loop.sh) \
    $(pids_by_cmd /userdata/rsyslog/bundle/) $(pids_by_cmd /userdata/bin/lighttpd) \
    $(pids_by_cmd "$SDCARD/bin/start-httpd.sh")
  stop TERM 10 $(pids_on_card)
}

if [ "$DRY" = 1 ]; then
  log "would sync, unmount $SDCARD, close the ssh/telnet sessions ($(pids_by_argv0 dropbear | tr '\n' ' ')$(
    pids_by_argv0 telnetd | tr '\n' ' ')) and reboot -f"
  exit 0
fi

sync
unmounted=0
if grep -q " $SDCARD " /proc/mounts; then
  for i in 1 2 3 4 5; do
    if umount "$SDCARD" 2>/dev/null; then
      unmounted=1
      break
    fi
    sleep 1
  done
else
  unmounted=1
fi
if [ "$unmounted" = 1 ]; then
  log "$SDCARD unmounted"
elif mount -o remount,ro "$SDCARD" 2>/dev/null; then
  log "WARNING: $SDCARD still busy, remounted read-only instead"
else
  log "WARNING: $SDCARD still busy and read-write; holders: $(pids_on_card | tr '\n' ' ')"
fi

sync
log "closing ssh/telnet sessions and rebooting in 1 s"
# The subshell keeps no fd of the session, so the session that runs this script ends right away. kill(-1) is
# not used: it would also stop wpa_supplicant, and the FIN packets would not leave over the dropped Wi-Fi.
(
  sleep 1
  # shellcheck disable=SC2046 # word splitting of pid lists is intended
  kill $(pids_by_argv0 dropbear) $(pids_by_argv0 telnetd) 2>/dev/null
  sleep 1
  reboot -f
) < /dev/null > /dev/null 2>&1 &
exit 0
