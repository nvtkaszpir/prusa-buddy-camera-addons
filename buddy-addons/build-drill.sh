#!/usr/bin/env bash
# Build a static, stripped drill (the dig-like DNS lookup tool from NLnet Labs
# ldns) for the Prusa/Buddy3D camera (ARMv7l, musl).
# Output: buddy-addons/out/drill
#
# Built without OpenSSL to keep the binary small: plain queries, +trace (-T),
# TCP, EDNS and DNSSEC record display all work; signature validation (-D with
# -k, -S chasing) does not.
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

LDNS_VER=1.9.2
LDNS_URL="https://nlnetlabs.nl/downloads/ldns/ldns-${LDNS_VER}.tar.gz"
LDNS_SHA256=b524fa21994b6e834200ceb8c27f1b84bda5982fe35706f058196c079db94d5d

SRC="$BUILD/ldns-${LDNS_VER}"

# Fresh tree every run so the script is rebuildable from scratch.
rm -rf "$SRC"
LDNS_TAR="$(fetch "$LDNS_URL" "$LDNS_SHA256")"
tar -xzf "$LDNS_TAR" -C "$BUILD"

(
  cd "$SRC"
  ./configure \
    --host="$CROSS_TRIPLE" \
    --enable-static \
    --disable-shared \
    --with-drill \
    --without-ssl \
    --without-pyldns \
    --without-pyldnsx \
    --without-p5-dns-ldns \
    --disable-sha2 \
    --disable-gost \
    --disable-ecdsa \
    --disable-dsa \
    --disable-ed25519 \
    --disable-ed448 \
    --disable-dane
  # "drill" also sets up the build-dir config.h shim. -all-static makes
  # libtool pass -static to the final link instead of linking libldns.so.
  make -j"$(nproc)" drill LDFLAGS="$LDFLAGS -all-static"
)

# ---- output -----------------------------------------------------------------
"${STRIP}" -s -o "$OUT/drill" "$SRC/drill/drill"
chmod 0755 "$OUT/drill"

echo "---- build summary ----"
file "$OUT/drill"
echo "ldns version: ${LDNS_VER} (${LDNS_URL})"
echo "ldns tarball sha256: ${LDNS_SHA256}"
echo "output: $OUT/drill"
echo "output sha256: $(sha256sum "$OUT/drill" | cut -d' ' -f1)"
echo "output size: $(stat -c %s "$OUT/drill") bytes"
