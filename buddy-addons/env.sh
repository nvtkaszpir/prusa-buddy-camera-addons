# Shared cross-compile settings for the Prusa Buddy3D camera.
# Target: Rockchip ARMv7l (Cortex-A7, NEON, VFPv4, hard-float), Linux 5.10,
# ubifs read-only rootfs, busybox/uClibc userland. Binaries are fully static
# musl so they do not depend on the device's libc.
#
# Sourced by build-*.sh. When called on the host, the build script re-execs
# itself inside the dockcross/linux-armv7l-musl image (provides $CC, $CROSS_TRIPLE).

IMAGE="${IMAGE:-dockcross/linux-armv7l-musl}"

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DL="$TOP/dl"        # downloaded source tarballs (cached, checksummed)
BUILD="$TOP/build"  # scratch build trees
OUT="$TOP/out"      # final stripped binaries to copy to the camera

TARGET_CFLAGS="-Os -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -ffunction-sections -fdata-sections"
TARGET_LDFLAGS="-static -Wl,--gc-sections"

# Host side: re-run the calling script inside the cross container with all args.
# Container side: export the cross flags.
toolchain_init() {
  if [ -z "${CROSS_TRIPLE:-}" ]; then
    mkdir -p "$DL" "$BUILD" "$OUT"
    exec docker run --rm -u "$(id -u):$(id -g)" \
      -v "$TOP:$TOP" -w "$TOP" -e HOME=/tmp \
      "$IMAGE" bash "$TOP/$(basename "$0")" "$@"
  fi
  export CFLAGS="$TARGET_CFLAGS"
  export CXXFLAGS="$TARGET_CFLAGS"
  export LDFLAGS="$TARGET_LDFLAGS"
  export STRIP="${CROSS_TRIPLE}-strip"
  mkdir -p "$DL" "$BUILD" "$OUT"
}

# fetch URL [SHA256] -> prints local path; downloads once, verifies if SHA256 given.
fetch() {
  local url="$1" sum="${2:-}" f="$DL/${1##*/}"
  if [ ! -f "$f" ]; then
    curl -fL --retry 3 -o "$f.part" "$url" || { rm -f "$f.part"; echo "download failed: $url" >&2; exit 1; }
    mv "$f.part" "$f"
  fi
  if [ -n "$sum" ]; then
    echo "$sum  $f" | sha256sum -c - >&2 || { echo "checksum mismatch: $f" >&2; exit 1; }
  else
    echo "sha256 (pin this in the build script): $(sha256sum "$f" | cut -d' ' -f1)" >&2
  fi
  echo "$f"
}
