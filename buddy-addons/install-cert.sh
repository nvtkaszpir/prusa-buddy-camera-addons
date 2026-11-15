#!/usr/bin/env bash
# Install a host-generated key and certificate (see gen-cert.sh) as the
# camera's lighttpd TLS identity, over the dropbear ssh server.
#
# Usage: ./install-cert.sh [--dir DIR] [--port N] SSH_TARGET
#   SSH_TARGET    e.g. root@192.168.1.75 or an ~/.ssh/config host alias
#   --dir DIR     directory with server.key and server.crt (default: the only
#                 directory under certs/)
#   --port N      HTTPS port to check afterwards (default: 8443)
#
# The files go to /userdata/httpd/server.{key,crt}; the previous pair is kept
# as server.{key,crt}.bak. start-httpd.sh only generates a certificate when
# none exists, so the installed one stays across reboots. If lighttpd rejects
# the new pair ("lighttpd -tt" in start-httpd.sh), the previous pair is put back.
set -euo pipefail

cd "$(dirname "$0")"

dir=""
port=8443
target=""

die() { echo "install-cert.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="${2:?--dir needs a value}"; shift 2 ;;
    --port) port="${2:?--port needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) [ -z "$target" ] || die "only one SSH_TARGET allowed"; target="$1"; shift ;;
  esac
done
[ -n "$target" ] || die "missing SSH_TARGET (see --help)"

if [ -z "$dir" ]; then
  shopt -s nullglob
  dirs=(certs/*/)
  [ "${#dirs[@]}" = 1 ] || die "pass --dir: found ${#dirs[@]} directories under certs/"
  dir="${dirs[0]%/}"
fi
key="$dir/server.key"
crt="$dir/server.crt"
[ -f "$key" ] && [ -f "$crt" ] || die "$dir must contain server.key and server.crt"

# Refuse a pair that cannot work before touching the camera.
[ "$(openssl pkey -in "$key" -pubout)" = "$(openssl x509 -in "$crt" -noout -pubkey)" ] \
  || die "$key does not belong to $crt"
openssl x509 -in "$crt" -noout -checkend 0 > /dev/null || die "$crt has expired"
local_fp=$(openssl x509 -in "$crt" -noout -fingerprint -sha256 | cut -d= -f2)

remote=/userdata/httpd
scp -O -q "$key" "$target:$remote/server.key.up"
scp -O -q "$crt" "$target:$remote/server.crt.up"

# busybox sh on the camera.
ssh "$target" sh -s <<'EOF'
set -e
cd /userdata/httpd
chmod 600 server.key.up
for f in server.key server.crt; do
  if [ -f "$f" ]; then cp "$f" "$f.bak"; fi
done
mv server.key.up server.key
mv server.crt.up server.crt
if sh /mnt/sdcard/bin/start-httpd.sh restart; then
  echo "installed; lighttpd restarted"
else
  echo "start-httpd.sh rejected the new pair, restoring the previous one (see /mnt/sdcard/logs/httpd.log)" >&2
  for f in server.key server.crt; do
    if [ -f "$f.bak" ]; then mv "$f.bak" "$f"; fi
  done
  sh /mnt/sdcard/bin/start-httpd.sh restart
  exit 1
fi
EOF

# Real host name, also for ~/.ssh/config aliases.
host=$(ssh -G "$target" 2> /dev/null | sed -n 's/^hostname //p')
host="${host:-${target#*@}}"
served_fp=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2> /dev/null \
  | openssl x509 -noout -fingerprint -sha256 2> /dev/null | cut -d= -f2) || true
echo "local  sha256: $local_fp"
echo "served sha256: ${served_fp:-<no answer on $host:$port>}"
[ "$served_fp" = "$local_fp" ] || die "the camera does not serve the new certificate"
