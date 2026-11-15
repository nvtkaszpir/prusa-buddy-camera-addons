#!/usr/bin/env bash
# Add, change or delete a user in the htpasswd file for lighttpd's HTTP basic
# auth (needs openssl 1.1.1 or newer for SHA-512 crypt).
#
# Usage: ./gen-htpasswd.sh [--file FILE] [--random | --delete] USER
#   --file FILE   htpasswd file to update (default: secrets/htpasswd)
#   --random      generate a random password and print it once
#   --delete      remove USER from the file
# Without --random the password is asked twice on a terminal, or read as one
# line from stdin when stdin is not a terminal.
#
# Then copy the file to the card and apply it:
#   scp -O secrets/htpasswd root@CAMERA_IP:/mnt/sdcard/bin/htpasswd
#   ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-httpd.sh
# secrets/ is in .gitignore.
set -euo pipefail

cd "$(dirname "$0")"

file=secrets/htpasswd
mode=set
user=""

die() { echo "gen-htpasswd.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="${2:?--file needs a value}"; shift 2 ;;
    --random) mode=random; shift ;;
    --delete) mode=delete; shift ;;
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) [ -z "$user" ] || die "only one USER allowed"; user="$1"; shift ;;
  esac
done
[ -n "$user" ] || die "missing USER (see --help)"
[[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || die "USER may only contain A-Z a-z 0-9 . _ -"
command -v openssl > /dev/null || die "openssl not found"

umask 077
mkdir -p "$(dirname "$file")"
touch "$file"

# Lines of all other users (exact field match; "." in USER is not a wildcard).
others=$(awk -F: -v u="$user" '$1 != u' "$file")

if [ "$mode" = delete ]; then
  awk -F: -v u="$user" '$1 == u { found = 1 } END { exit !found }' "$file" || die "no user $user in $file"
  printf '%s' "$others${others:+$'\n'}" > "$file.new"
  mv "$file.new" "$file"
  echo "deleted $user from $file"
  exit 0
fi

if [ "$mode" = random ]; then
  pw=$(openssl rand -base64 18 | tr '+/' '-_')
elif [ -t 0 ]; then
  read -r -s -p "password for $user: " pw; echo
  read -r -s -p "again: " pw2; echo
  [ "$pw" = "$pw2" ] || die "passwords differ"
else
  IFS= read -r pw || true
fi
[ -n "$pw" ] || die "empty password"

hash=$(printf '%s\n' "$pw" | openssl passwd -6 -stdin)
printf '%s%s%s:%s\n' "$others" "${others:+$'\n'}" "$user" "$hash" > "$file.new"
mv "$file.new" "$file"
chmod 600 "$file"

echo "set password for $user in $file"
[ "$mode" = random ] && echo "password: $pw"
exit 0
