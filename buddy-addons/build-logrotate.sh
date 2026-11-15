#!/usr/bin/env bash
# Build a static, stripped logrotate 3.22.0 (with a static popt 1.19) for the Prusa/Buddy3D
# camera (ARMv7l, musl). Output: buddy-addons/out/logrotate
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export CXXFLAGS="$CXXFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

LOGROTATE_VER=3.22.0
LOGROTATE_URL="https://github.com/logrotate/logrotate/releases/download/${LOGROTATE_VER}/logrotate-${LOGROTATE_VER}.tar.xz"
LOGROTATE_SHA256=42b4080ee99c9fb6a7d12d8e787637d057a635194e25971997eebbe8d5e57618

# logrotate links libpopt unconditionally (configure.ac: AC_MSG_ERROR without it).
# popt publishes no checksum next to its tarball; this pin is the sha256 of the
# tarball from ftp.rpm.org when this script was written.
POPT_VER=1.19
POPT_URL="http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VER}.tar.gz"
POPT_SHA256=c25a4838fc8e4c1c8aacb8bd620edb3084a3d63bf8987fdad3ca2758c63240f9

HOST_TRIPLE="${CROSS_TRIPLE:-armv7l-linux-musleabihf}"
PREFIX="$BUILD/prefix-logrotate"
SRC="$BUILD/logrotate-${LOGROTATE_VER}"
PSRC="$BUILD/popt-${POPT_VER}"

# Fresh trees every run so the script is rebuildable from scratch.
rm -rf "$SRC" "$PSRC" "$PREFIX"
mkdir -p "$PREFIX"

LOGROTATE_TAR="$(fetch "$LOGROTATE_URL" "$LOGROTATE_SHA256")"
POPT_TAR="$(fetch "$POPT_URL" "$POPT_SHA256")"

# ---- popt (static, into prefix) ---------------------------------------------
tar -xzf "$POPT_TAR" -C "$BUILD"
(
  cd "$PSRC"
  ./configure \
    --host="$HOST_TRIPLE" \
    --prefix="$PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-nls
  make -j"$(nproc)"
  make install
)

# ---- logrotate ----------------------------------------------------------------
tar -xJf "$LOGROTATE_TAR" -C "$BUILD"
(
  cd "$SRC"
  CPPFLAGS="-I$PREFIX/include" \
  LDFLAGS="-L$PREFIX/lib $LDFLAGS -static" \
  ./configure \
    --host="$HOST_TRIPLE" \
    --without-selinux \
    --without-acl
  make -j"$(nproc)"
)

# ---- output -------------------------------------------------------------------
"${STRIP:-strip}" -s "$SRC/logrotate"
cp "$SRC/logrotate" "$OUT/logrotate"
chmod 0755 "$OUT/logrotate"

echo "---- build summary ----"
file "$OUT/logrotate"
echo "logrotate version: ${LOGROTATE_VER} (${LOGROTATE_URL})"
echo "logrotate tarball sha256: ${LOGROTATE_SHA256}"
echo "popt version: ${POPT_VER} (${POPT_URL})"
echo "popt tarball sha256: ${POPT_SHA256}"
echo "output: $OUT/logrotate"
echo "output sha256: $(sha256sum "$OUT/logrotate" | cut -d' ' -f1)"
echo "output size: $(stat -c %s "$OUT/logrotate") bytes"
