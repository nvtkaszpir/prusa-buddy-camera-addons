#!/bin/sh
# Start lighttpd (read-only HTTP/HTTPS file server for the microSD card).
# Idempotent; run on every boot.
#
# Usage: sh start-httpd.sh [restart|stop]
#   (no argument)  install/refresh files, start if not running, restart if the
#                  binary or config changed on the card
#   restart        same, but always restart a running server
#   stop           stop a running server and exit
#
# Layout:
#   /userdata/bin/lighttpd, mbedtls-gen-key, mbedtls-cert-write   copied from the card
#   /userdata/httpd/                  mode 700
#   /userdata/httpd/lighttpd.conf     from /mnt/sdcard/bin/lighttpd.conf (card wins)
#   /userdata/httpd/dirlisting-header.tmpl   from /mnt/sdcard/bin/dirlisting-header.html
#                                     (card wins), optional: <head>, CSS and title of
#                                     directory listings
#   /userdata/httpd/dirlisting-header.html   the template with @HOSTNAME@/@FQDN@ filled
#                                     in (reverse DNS via drill, else hostname); re-read
#                                     by lighttpd per listing, so no restart for it
#   /tmp/httpd-title.pid              background reverse-DNS retry after boot
#   /userdata/httpd/htpasswd          from /mnt/sdcard/bin/htpasswd (card wins), mode 600:
#                                     users for HTTP basic auth; a change restarts
#                                     lighttpd so its login cache is dropped
#   /userdata/httpd/server.key        ECDSA P-256, generated on first start
#   /userdata/httpd/server.crt        self-signed for CN=$(hostname), generated on first start,
#                                     valid for 10 years from generation (UTC)
#   /tmp/lighttpd.pid, /tmp/lighttpd.log   server pid file and error log
#
# The microSD card (/mnt/sdcard/bin) is the source of truth. A new config is
# checked with "lighttpd -tt" before it replaces the installed one; a broken
# config is logged and ignored, and a running server is never stopped for it.
# Delete server.key and server.crt to get a new certificate on the next start.

SRC=/mnt/sdcard/bin
BIN=/userdata/bin
DIR=/userdata/httpd
CONF=$DIR/lighttpd.conf
KEY=$DIR/server.key
CRT=$DIR/server.crt
PIDFILE=/tmp/lighttpd.pid
SRVLOG=/tmp/lighttpd.log

if [ -d /mnt/sdcard/logs ]; then LOG=/mnt/sdcard/logs/httpd.log; else LOG=/tmp/httpd.log; fi
log() { echo "start-httpd: $*" >> "$LOG"; }
md5() { md5sum < "$1" | cut -d' ' -f1; }

# Running lighttpd pid on stdout; fails if none.
running_pid() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && grep -q lighttpd "/proc/$pid/cmdline" 2>/dev/null || return 1
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
  log "stopped lighttpd (pid $pid)"
}

case "$1" in
  stop) stop_server; exit 0 ;;
  restart) restart=1 ;;
  "") restart=0 ;;
  *) echo "usage: $0 [restart|stop]" >&2; exit 2 ;;
esac

mkdir -p "$BIN" "$DIR"
chmod 700 "$DIR"

# Refresh binaries from the card when their content differs. A running
# lighttpd keeps its old (replaced) file open, so mv is safe.
# drill (reverse DNS for the listing title) is also installed by start-sshd.sh;
# doing it here too keeps lighttpd independent of the ssh add-on.
for f in lighttpd mbedtls-gen-key mbedtls-cert-write drill; do
  if [ -f "$SRC/$f" ]; then
    new=$(md5 "$SRC/$f")
    old=""
    [ -f "$BIN/$f" ] && old=$(md5 "$BIN/$f")
    if [ "$new" != "$old" ]; then
      cp "$SRC/$f" "$BIN/$f.new" && mv "$BIN/$f.new" "$BIN/$f"
      log "installed $f (md5 $new)"
      [ "$f" = lighttpd ] && restart=1
    fi
  fi
  [ -f "$BIN/$f" ] && chmod 755 "$BIN/$f"
done

if [ ! -x "$BIN/lighttpd" ]; then
  log "no $BIN/lighttpd, cannot start httpd"
  exit 1
fi

# Certificate and key, generated once. Needed before "lighttpd -tt", which
# loads them when the config enables TLS.
if [ ! -f "$KEY" ] || [ ! -f "$CRT" ]; then
  if [ ! -x "$BIN/mbedtls-gen-key" ] || [ ! -x "$BIN/mbedtls-cert-write" ]; then
    log "no $BIN/mbedtls-gen-key or $BIN/mbedtls-cert-write, cannot create TLS certificate"
    exit 1
  fi
  # Only characters that are safe inside an X.509 DN / DNS SAN.
  cn=$(hostname | sed 's/[^A-Za-z0-9.-]//g')
  [ -n "$cn" ] || cn=camera
  rm -f "$KEY" "$CRT" "$KEY.new" "$CRT.new"
  # stdout of both tools goes to /dev/null: mbedtls-gen-key prints the private
  # key there, and $LOG may be on the card, which this server publishes.
  if ! "$BIN/mbedtls-gen-key" type=ec ec_curve=secp256r1 format=pem \
       filename="$KEY.new" > /dev/null 2>> "$LOG"; then
    rm -f "$KEY.new"
    log "mbedtls-gen-key failed"
    exit 1
  fi
  chmod 600 "$KEY.new"
  # Serial derived from the key, so a regenerated certificate never reuses
  # issuer+serial (Firefox rejects that). Leading 01 keeps it positive.
  serial=01$(md5 "$KEY.new" | cut -c1-14)
  # Valid for 10 years (UTC, YYYYMMDDhhmmss), starting 1 hour before now so
  # clients whose clocks lag a little do not see "not yet valid". With an
  # unset clock (before 2025) start at 2025-01-01 instead.
  # 29 Feb + 10 years -> 28 Feb.
  now=$(date -u -d "@$(( $(date +%s) - 3600 ))" +%Y%m%d%H%M%S)
  year=${now%??????????}
  rest=${now#????}
  if [ "$year" -lt 2025 ]; then
    log "WARNING: clock is $now (not set); certificate starts 2025-01-01. Delete $KEY and $CRT and rerun $0 once the clock is right."
    year=2025
    rest=0101000000
  fi
  case "$rest" in 0229*) rest_after=0228${rest#0229} ;; *) rest_after=$rest ;; esac
  not_before=$year$rest
  not_after=$((year + 10))$rest_after
  if ! "$BIN/mbedtls-cert-write" selfsign=1 issuer_key="$KEY.new" \
       issuer_name="CN=$cn" san="DNS:$cn" serial_hex="$serial" \
       not_before="$not_before" not_after="$not_after" \
       is_ca=0 md=SHA256 format=pem output_file="$CRT.new" > /dev/null 2>> "$LOG"; then
    rm -f "$KEY.new" "$CRT.new"
    log "mbedtls-cert-write failed"
    exit 1
  fi
  mv "$KEY.new" "$KEY" && mv "$CRT.new" "$CRT"
  log "generated self-signed certificate $CRT for CN=$cn, valid $not_before to $not_after (UTC)"
  # SHA-256 fingerprint of the DER certificate, if busybox has the tools;
  # otherwise compute it on the host: openssl x509 -noout -fingerprint -sha256 -in server.crt
  if command -v sha256sum >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
    fp=$(sed -n '/-BEGIN/,/-END/p' "$CRT" | grep -v -- '-----' | base64 -d 2>/dev/null \
         | sha256sum | cut -d' ' -f1 | sed 's/../&:/g; s/:$//; y/abcdef/ABCDEF/')
    [ -n "$fp" ] && log "certificate SHA256 fingerprint $fp"
  else
    log "no sha256sum/base64 here; get the fingerprint on the host from a copy of $CRT"
  fi
fi

# Refresh the config from the card (card wins), but only if it passes
# "lighttpd -tt"; otherwise keep the installed one.
conf_bad=0
if [ -f "$SRC/lighttpd.conf" ]; then
  new=$(md5 "$SRC/lighttpd.conf")
  old=""
  [ -f "$CONF" ] && old=$(md5 "$CONF")
  if [ "$new" != "$old" ]; then
    cp "$SRC/lighttpd.conf" "$CONF.new"
    if out=$("$BIN/lighttpd" -tt -f "$CONF.new" 2>&1 < /dev/null); then
      mv "$CONF.new" "$CONF"
      log "installed lighttpd.conf (md5 $new)"
      restart=1
    else
      rm -f "$CONF.new"
      log "REJECTED $SRC/lighttpd.conf (md5 $new), keeping the installed config. lighttpd -tt said:"
      echo "$out" >> "$LOG"
      conf_bad=1
    fi
  fi
fi

# Listing header template (<head>, CSS, title), card wins. Its @HOSTNAME@ and
# @FQDN@ placeholders are filled in below. lighttpd reads the rendered file for
# every listing, so no restart; without it listings are a bare table.
HDR=dirlisting-header.html
TPL=$DIR/dirlisting-header.tmpl
if [ -f "$SRC/$HDR" ]; then
  new=$(md5 "$SRC/$HDR")
  old=""
  [ -f "$TPL" ] && old=$(md5 "$TPL")
  if [ "$new" != "$old" ]; then
    cp "$SRC/$HDR" "$TPL.new" && mv "$TPL.new" "$TPL"
    log "installed $HDR (md5 $new)"
  fi
fi

# Full DNS name of the camera: PTR record of its first non-loopback IPv4
# address, looked up with drill. Optional argument: give up after that many
# seconds (busybox timeout); without it drill's own retries apply (~15 s when
# a DNS server does not answer).
camera_fqdn() {
  [ -x "$BIN/drill" ] || return 1
  ip=$(ifconfig 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | grep -v '^127\.' | head -n 1)
  [ -n "$ip" ] || return 1
  if [ -n "$1" ] && command -v timeout > /dev/null 2>&1; then
    set -- timeout -t "$1" "$BIN/drill" -x "$ip"
  else
    set -- "$BIN/drill" -x "$ip"
  fi
  # Answer lines only: the ";;" question line also has PTR as 4th field.
  name=$("$@" 2>/dev/null | awk '$1 !~ /^;/ && $4 == "PTR" { print $5; exit }')
  name=${name%.}
  case "$name" in ""|*[!A-Za-z0-9.-]*) return 1 ;; esac
  echo "$name"
}

# render_header NAME: fill the placeholders. @HOSTNAME@ = NAME up to the first
# dot, @FQDN@ = NAME if it has a dot, else empty.
render_header() {
  [ -f "$TPL" ] || return 0
  short=${1%%.*}
  case "$1" in *.*) full=$1 ;; *) full="" ;; esac
  sed -e "s/@HOSTNAME@/$short/g" -e "s/@FQDN@/$full/g" "$TPL" > "$DIR/$HDR.new" \
    && mv "$DIR/$HDR.new" "$DIR/$HDR"
}

# Use the DNS name if it is known now; otherwise show hostname and keep asking
# DNS in the background (the network is usually not up yet at boot) for up to
# 10 minutes. Only one such job runs at a time.
TITLEPID=/tmp/httpd-title.pid
if [ -f "$TPL" ]; then
  if fqdn=$(camera_fqdn 5); then
    render_header "$fqdn"
    log "listing title: $fqdn (reverse DNS)"
    # A retry job from an earlier run is no longer needed.
    if [ -f "$TITLEPID" ]; then
      kill "$(cat "$TITLEPID")" 2>/dev/null
      rm -f "$TITLEPID"
    fi
  else
    host=$(hostname | sed 's/[^A-Za-z0-9.-]//g')
    render_header "${host:-camera}"
    if [ ! -x "$BIN/drill" ]; then
      log "listing title: ${host:-camera} (no $BIN/drill for reverse DNS)"
    elif [ -f "$TITLEPID" ] && kill -0 "$(cat "$TITLEPID")" 2>/dev/null; then
      log "listing title: ${host:-camera} for now; reverse DNS lookup already running"
    else
      log "listing title: ${host:-camera} for now; retrying reverse DNS in the background"
      (
        cd /
        i=0
        while [ "$i" -lt 40 ]; do
          sleep 15
          if fqdn=$(camera_fqdn); then
            render_header "$fqdn"
            log "listing title: $fqdn (reverse DNS)"
            break
          fi
          i=$((i + 1))
        done
        [ "$i" -lt 40 ] || log "no reverse DNS name after 10 minutes; listing title stays ${host:-camera}"
        rm -f "$TITLEPID"
      ) < /dev/null > /dev/null 2>&1 &
      echo $! > "$TITLEPID"
    fi
  fi
fi

# Basic-auth users, card wins. Restart on change so lighttpd's auth.cache does
# not keep accepting removed users or old passwords.
PW=htpasswd
if [ -f "$SRC/$PW" ]; then
  new=$(md5 "$SRC/$PW")
  old=""
  [ -f "$DIR/$PW" ] && old=$(md5 "$DIR/$PW")
  if [ "$new" != "$old" ]; then
    cp "$SRC/$PW" "$DIR/$PW.new" && chmod 600 "$DIR/$PW.new" && mv "$DIR/$PW.new" "$DIR/$PW"
    log "installed $PW (md5 $new)"
    restart=1
  fi
fi
if [ ! -s "$DIR/$PW" ] && grep -q '^[^#]*auth\.backend\.htpasswd\.userfile' "$CONF" 2>/dev/null; then
  log "WARNING: no $DIR/$PW (copy one to $SRC/$PW); every request will get 401"
fi

if [ ! -f "$CONF" ]; then
  log "no $CONF, cannot start httpd"
  exit 1
fi

# Check the installed config (with a possibly new binary) before touching a
# running server.
if ! out=$("$BIN/lighttpd" -tt -f "$CONF" 2>&1 < /dev/null); then
  log "config check of $CONF failed, not (re)starting. lighttpd -tt said:"
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

# lighttpd daemonizes itself and writes $PIDFILE. cwd / and logs in /tmp, so
# it holds nothing open on /mnt/sdcard except files being served.
rm -f "$PIDFILE"
if (cd / && exec "$BIN/lighttpd" -f "$CONF") < /dev/null >> "$SRVLOG" 2>&1 \
   && pid=$(running_pid); then
  log "started lighttpd (pid $pid)"
else
  log "lighttpd failed to start, see $SRVLOG"
  exit 1
fi
exit "$conf_bad"
