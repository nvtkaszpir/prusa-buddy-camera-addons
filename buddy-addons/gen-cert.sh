#!/usr/bin/env bash
# Generate a TLS key and self-signed certificate for the camera's lighttpd on
# this host (needs openssl 1.1.1 or newer). Install it with install-cert.sh.
#
# Usage: ./gen-cert.sh [options]
#   --cn NAME     certificate common name (default: camera); also added as a DNS SAN
#   --dns NAME    extra DNS subjectAltName, repeatable
#   --ip ADDR     IP subjectAltName, repeatable (lets clients pin the cert while
#                 connecting by IP, without curl --resolve)
#   --days N      validity in days (default: 10 years from today, leap days included)
#   --out DIR     output directory (default: certs/<cn>)
#   --force       overwrite an existing key/certificate in DIR
#
# Output: DIR/server.key (ECDSA P-256, PKCS#8 PEM, mode 600) and DIR/server.crt
# (PEM), the same file names lighttpd.conf expects in /userdata/httpd/.
# certs/ is in .gitignore: it holds private keys.
set -euo pipefail

cd "$(dirname "$0")"

cn=camera
# Days until the same date 10 years from now (GNU date); 3653 = 10 years
# with the most leap days, if date -d is not available.
days=$(( ( $(date -u -d '+10 years' +%s 2> /dev/null || echo $(( $(date +%s) + 3653 * 86400 ))) - $(date +%s) ) / 86400 ))
out=""
force=0
dns=()
ips=()

die() { echo "gen-cert.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cn) cn="${2:?--cn needs a value}"; shift 2 ;;
    --dns) dns+=("${2:?--dns needs a value}"); shift 2 ;;
    --ip) ips+=("${2:?--ip needs a value}"); shift 2 ;;
    --days) days="${2:?--days needs a value}"; shift 2 ;;
    --out) out="${2:?--out needs a value}"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ "$cn" =~ ^[A-Za-z0-9.-]+$ ]] || die "--cn must be a host name ([A-Za-z0-9.-])"
[[ "$days" =~ ^[1-9][0-9]*$ ]] || die "--days must be a positive integer"
command -v openssl > /dev/null || die "openssl not found"

out="${out:-certs/$cn}"
key="$out/server.key"
crt="$out/server.crt"
if [ "$force" = 0 ] && { [ -e "$key" ] || [ -e "$crt" ]; }; then
  die "$out already has server.key or server.crt (use --force to replace)"
fi

san="DNS:$cn"
# ${a[@]+...}: empty arrays are "unbound" under set -u in bash < 4.4 (macOS).
for d in ${dns[@]+"${dns[@]}"}; do san="$san,DNS:$d"; done
for i in ${ips[@]+"${ips[@]}"}; do san="$san,IP:$i"; done

mkdir -p "$out"
chmod 700 "$out"
umask 077
openssl req -x509 -new -nodes \
  -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout "$key.new" -out "$crt.new" \
  -sha256 -days "$days" -subj "/CN=$cn" \
  -addext "subjectAltName=$san" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=serverAuth" 2> "$out/openssl.err" \
  || { cat "$out/openssl.err" >&2; rm -f "$key.new" "$crt.new" "$out/openssl.err"; exit 1; }
rm -f "$out/openssl.err"
mv "$key.new" "$key"
mv "$crt.new" "$crt"
chmod 600 "$key"
chmod 644 "$crt"

echo "key:         $key"
echo "certificate: $crt"
openssl x509 -in "$crt" -noout -subject -startdate -enddate -ext subjectAltName -fingerprint -sha256
