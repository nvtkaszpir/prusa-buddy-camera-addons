#!/usr/bin/env bash
# Build a static, stripped ntpsync (kernel clock sync probe) for the
# Prusa/Buddy3D camera (ARMv7l, musl).
# Output: buddy-addons/out/ntpsync
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

SRC_FILE="$(dirname "$0")/ntpsync.c"
BIN="$BUILD/ntpsync"

"$CC" $CFLAGS $LDFLAGS -static -o "$BIN" "$SRC_FILE"

# ---- output -----------------------------------------------------------------
"${STRIP:-strip}" -s "$BIN"
cp "$BIN" "$OUT/ntpsync"
chmod 0755 "$OUT/ntpsync"

echo "---- build summary ----"
file "$OUT/ntpsync"
echo "source: ntpsync.c"
echo "output: $OUT/ntpsync"
echo "output sha256: $(sha256sum "$OUT/ntpsync" | cut -d' ' -f1)"
echo "output size: $(stat -c %s "$OUT/ntpsync") bytes"
