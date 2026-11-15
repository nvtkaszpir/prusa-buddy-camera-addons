#!/usr/bin/env bash
# Build a static, stripped fsck.fat (dosfstools) for the Prusa/Buddy3D camera (ARMv7l, musl).
# Output: buddy-addons/out/fsck.fat
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export CXXFLAGS="$CXXFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

DOSFS_VER=4.2
DOSFS_URL="https://github.com/dosfstools/dosfstools/releases/download/v${DOSFS_VER}/dosfstools-${DOSFS_VER}.tar.gz"
DOSFS_SHA256=64926eebf90092dca21b14259a5301b7b98e7b1943e8a201c7d726084809b527

HOST_TRIPLE="${CROSS_TRIPLE:-armv7l-linux-musleabihf}"
SRC="$BUILD/dosfstools-${DOSFS_VER}"

# Fresh tree every run so the script is rebuildable from scratch.
rm -rf "$SRC"

DOSFS_TAR="$(fetch "$DOSFS_URL" "$DOSFS_SHA256")"

# ---- dosfstools ---------------------------------------------------------------
# --without-iconv: no libiconv in the static musl build; fsck.fat then shows
# short names in the default codepage only. libudev is only used by mkfs.fat
# and is not found in the cross container, so nothing to disable there.
tar -xzf "$DOSFS_TAR" -C "$BUILD"
(
  cd "$SRC"
  ./configure \
    --host="$HOST_TRIPLE" \
    --without-iconv \
    --without-libiconv-prefix
  make -j"$(nproc)" -C src fsck.fat
)

# ---- output -------------------------------------------------------------------
"${STRIP:-strip}" -s "$SRC/src/fsck.fat"
cp "$SRC/src/fsck.fat" "$OUT/fsck.fat"
chmod 0755 "$OUT/fsck.fat"

echo "---- build summary ----"
file "$OUT/fsck.fat"
echo "dosfstools version: ${DOSFS_VER} (${DOSFS_URL})"
echo "dosfstools tarball sha256: ${DOSFS_SHA256}"
echo "output: $OUT/fsck.fat"
echo "output sha256: $(sha256sum "$OUT/fsck.fat" | cut -d' ' -f1)"
echo "output size: $(stat -c %s "$OUT/fsck.fat") bytes"
