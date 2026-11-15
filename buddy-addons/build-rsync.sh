#!/usr/bin/env bash
# Build a static, stripped rsync 3.x for the Prusa/Buddy3D camera (ARMv7l, musl).
# Output: buddy-addons/out/rsync
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export CXXFLAGS="$CXXFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

RSYNC_VER=3.5.1
RSYNC_URL="https://download.samba.org/pub/rsync/src/rsync-${RSYNC_VER}.tar.gz"
RSYNC_SHA256=c55f9c9dc10fb8bec397b399a0fdded53cc9a2d8e30891bb0d63724d25c37bef

ZLIB_VER=1.3.2
ZLIB_URL="https://zlib.net/zlib-${ZLIB_VER}.tar.gz"
ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16

HOST_TRIPLE="${CROSS_TRIPLE:-armv7l-linux-musleabihf}"
PREFIX="$BUILD/prefix-rsync"
SRC="$BUILD/rsync-${RSYNC_VER}"
ZSRC="$BUILD/zlib-${ZLIB_VER}"

# Fresh trees every run so the script is rebuildable from scratch.
rm -rf "$SRC" "$ZSRC" "$PREFIX"
mkdir -p "$PREFIX"

RSYNC_TAR="$(fetch "$RSYNC_URL" "$RSYNC_SHA256")"
ZLIB_TAR="$(fetch "$ZLIB_URL" "$ZLIB_SHA256")"

# ---- zlib (static, into prefix) -------------------------------------------
tar -xzf "$ZLIB_TAR" -C "$BUILD"
(
  cd "$ZSRC"
  CC="$CC" AR="${CROSS_TRIPLE}-ar" RANLIB="${CROSS_TRIPLE}-ranlib" \
    CFLAGS="$CFLAGS" LDFLAGS="" \
    ./configure --static --prefix="$PREFIX"
  make -j"$(nproc)" libz.a
  make install
)

# ---- rsync ------------------------------------------------------------------
tar -xzf "$RSYNC_TAR" -C "$BUILD"
(
  cd "$SRC"
  CPPFLAGS="-I$PREFIX/include" \
  LDFLAGS="-L$PREFIX/lib $LDFLAGS -static" \
  ./configure \
    --host="$HOST_TRIPLE" \
    --disable-debug \
    --disable-md2man \
    --disable-iconv \
    --disable-iconv-open \
    --disable-idn \
    --disable-acl-support \
    --disable-xattr-support \
    --disable-openssl \
    --disable-zstd \
    --disable-lz4 \
    --disable-xxhash \
    --without-included-zlib
  make -j"$(nproc)"
)

# ---- output -----------------------------------------------------------------
"${STRIP:-strip}" -s "$SRC/rsync"
cp "$SRC/rsync" "$OUT/rsync"
chmod 0755 "$OUT/rsync"

echo "---- build summary ----"
file "$OUT/rsync"
echo "rsync version: ${RSYNC_VER} (${RSYNC_URL})"
echo "rsync tarball sha256: ${RSYNC_SHA256}"
echo "zlib version: ${ZLIB_VER} (${ZLIB_URL})"
echo "zlib tarball sha256: ${ZLIB_SHA256}"
echo "output: $OUT/rsync"
echo "output sha256: $(sha256sum "$OUT/rsync" | cut -d' ' -f1)"
echo "output size: $(stat -c %s "$OUT/rsync") bytes"
