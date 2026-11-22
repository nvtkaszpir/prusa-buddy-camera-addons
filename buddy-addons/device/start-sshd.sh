#!/bin/sh
# Start dropbear sshd (+ rsync, drill) on the camera. Idempotent; run on every boot.
#
# Layout:
#   /userdata/bin/dropbearmulti, rsync, drill   binaries (copied from the card)
#   /userdata/bin/{dropbear,dropbearkey,dbclient,scp}   applet links
#   /userdata/ssh/                               root's home for ssh (mode 700)
#   /userdata/ssh/authorized_keys                from /mnt/sdcard/bin/authorized_keys
#   /userdata/ssh/dropbear_ed25519_host_key      generated on first start
#   /userdata/ssh/passwd                         copy of /etc/passwd, root home = /userdata/ssh
#
# Why the passwd copy: dropbear refuses pubkey auth unless every directory from
# the authorized_keys path up to the user's home (or up to "/") is owned by
# root/user and not group/other-writable. On this camera "/" is owned by uid
# 1001 (mode 775 on firmware 3.1.3, 755 on 3.1.6), so keys under /userdata fail.
# Root's home /root does not help: the 3.1.0 dump has none, and the 3.1.6 rootfs
# has one owned by uid 1001 as well. Bind-mounting a passwd copy whose root home
# is /userdata/ssh makes the walk stop at /userdata/ssh.
#
# The microSD card (/mnt/sdcard/bin) is the source of truth: binaries and
# authorized_keys are refreshed from it on each start.

SRC=/mnt/sdcard/bin
BIN=/userdata/bin
SSHDIR=/userdata/ssh
HOSTKEY=$SSHDIR/dropbear_ed25519_host_key
PIDFILE=/tmp/dropbear.pid
PORT=22
# Server keepalive: dropbear sends a keepalive after KEEPALIVE seconds without traffic and drops the
# connection after 3 unanswered ones (DEFAULT_KEEPALIVE_LIMIT), so dead clients go away after ~15 s.
KEEPALIVE=5

if [ -d /mnt/sdcard/logs ]; then LOG=/mnt/sdcard/logs/dropbear.log; else LOG=/tmp/dropbear.log; fi
log() { echo "start-sshd: $*" >> "$LOG"; }

mkdir -p "$BIN" "$SSHDIR"
chmod 700 "$SSHDIR"

# Refresh binaries from the card when their content differs.
restart=0
for f in dropbearmulti rsync drill; do
  if [ -f "$SRC/$f" ]; then
    new=$(md5sum < "$SRC/$f" | cut -d' ' -f1)
    old=""
    [ -f "$BIN/$f" ] && old=$(md5sum < "$BIN/$f" | cut -d' ' -f1)
    if [ "$new" != "$old" ]; then
      cp "$SRC/$f" "$BIN/$f.new" && mv "$BIN/$f.new" "$BIN/$f"
      log "installed $f (md5 $new)"
      [ "$f" = dropbearmulti ] && restart=1
    fi
  fi
  [ -f "$BIN/$f" ] && chmod 755 "$BIN/$f"
done

if [ ! -x "$BIN/dropbearmulti" ]; then
  log "no $BIN/dropbearmulti, cannot start sshd"
  exit 1
fi

for applet in dropbear dropbearkey dbclient scp; do
  [ -e "$BIN/$applet" ] || ln -s dropbearmulti "$BIN/$applet"
done

# Refresh authorized_keys from the card (card is authoritative).
if [ -f "$SRC/authorized_keys" ]; then
  new_keys=$(md5sum < "$SRC/authorized_keys" | cut -d' ' -f1)
  old_keys=""
  [ -f "$SSHDIR/authorized_keys" ] && old_keys=$(md5sum < "$SSHDIR/authorized_keys" | cut -d' ' -f1)
  if [ "$new_keys" != "$old_keys" ]; then
    cp "$SRC/authorized_keys" "$SSHDIR/authorized_keys"
    chmod 600 "$SSHDIR/authorized_keys"
    log "installed authorized_keys from microSD"
  fi
fi

if [ ! -f "$HOSTKEY" ]; then
  "$BIN/dropbearkey" -t ed25519 -f "$HOSTKEY" >> "$LOG" 2>&1
  log "generated host key"
fi

# Make root's home /userdata/ssh so pubkey auth works (see header).
if ! grep -q ' /etc/passwd ' /proc/mounts; then
  sed '/^root:/s#:/root:#:/userdata/ssh:#' /etc/passwd > "$SSHDIR/passwd"
  if ! mount --bind "$SSHDIR/passwd" /etc/passwd; then
    log "bind mount of /etc/passwd failed; pubkey login will not work"
    exit 1
  fi
  log "bound $SSHDIR/passwd over /etc/passwd"
fi

# Restart a running server if the dropbear binary changed on the card, or if it was started with other
# options (e.g. without -K by an older version of this script). Open sessions keep running.
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  case "$(tr '\0' ' ' < "/proc/$(cat "$PIDFILE")/cmdline")" in
    *" -K $KEEPALIVE "*) ;;
    *) restart=1 ;;
  esac
fi
if [ "$restart" = 1 ] && [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")"
  rm -f "$PIDFILE"
  log "stopped old dropbear to load the new binary or options"
fi

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  log "already running (pid $(cat "$PIDFILE"))"
  exit 0
fi

# -D: directory with authorized_keys. -r: ed25519 host key only.
# -m: no motd (keeps remote command stdout clean for rsync/scp). -K: keepalive (see KEEPALIVE).
# Password logins are compiled out of this build.
# The daemon's own log goes to /tmp and it runs with cwd /, so it never holds
# a file on /mnt/sdcard open: the boot hook unmounts and remounts the card
# right after this script, and an open file would make that umount fail.
(cd / && exec "$BIN/dropbear" -F -m -p "$PORT" -K "$KEEPALIVE" -r "$HOSTKEY" -D "$SSHDIR" -P "$PIDFILE" \
  < /dev/null >> /tmp/dropbear.log 2>&1) &
log "started dropbear on port $PORT (keepalive ${KEEPALIVE} s)"
