#!/usr/bin/env bash
# Build rsyslog 8.x for the Prusa/Buddy3D camera (ARMv7l, musl) as a small
# self-contained bundle: dynamic musl rsyslogd + its own musl loader, the three
# shared libraries it needs and only the modules the camera config uses.
# Output: buddy-addons/out/rsyslog/ (flat directory, no symlinks, vfat-safe)
#
# Why not one static binary like the other add-ons: rsyslogd loads its inputs
# (imuxsock, imklog, imfile) and the network helpers omfwd needs (lmnet,
# lmnetstrms, lmnsd_ptcp, lmtcpclt) with dlopen(). musl's dlopen() always fails
# in a static binary, so a static rsyslogd cannot load any module. The bundle
# ships musl's dynamic loader (ld-musl-armhf.so.1, which is also libc), so it
# never touches the camera's uClibc. Start it as:
#   DIR/ld-musl-armhf.so.1 --library-path DIR DIR/rsyslogd -M DIR -f CONF ...
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Dynamic build: drop env.sh's "-static". -static-libgcc keeps libgcc_s.so
# out of the bundle (passed via CC so libtool cannot drop it).
export LDFLAGS="-Wl,--gc-sections -Wl,--as-needed"
CCX="$CC -static-libgcc"

RSYSLOG_VER=8.2610.0
RSYSLOG_URL="https://www.rsyslog.com/files/download/rsyslog/rsyslog-${RSYSLOG_VER}.tar.gz"
RSYSLOG_SHA256=7bdf95e81ea6c0ee5d586342d57d2a6e395b089fb3c67318a0dc555816de404b

LIBESTR_VER=0.1.11
LIBESTR_URL="https://libestr.adiscon.com/files/download/libestr-${LIBESTR_VER}.tar.gz"
LIBESTR_SHA256=46632b2785ff4a231dcf241eeb0dcb5fc0c7d4da8ee49cf5687722cdbe8b2024

LIBFASTJSON_VER=1.2609.0
LIBFASTJSON_URL="https://download.rsyslog.com/libfastjson/libfastjson-${LIBFASTJSON_VER}.tar.gz"
LIBFASTJSON_SHA256=7cd6f78c1c07f4140f6976a9a0e0048bcaa7292329c6ac2c0e070383d83d8edd

ZLIB_VER=1.3.2
ZLIB_URL="https://zlib.net/zlib-${ZLIB_VER}.tar.gz"
ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16

# Modules shipped in the bundle (everything else rsyslog builds is left out).
# imuxsock: /dev/log, imklog: /proc/kmsg, imfile: tail files.
# omfwd itself is built into rsyslogd. It needs lmnet (also used by imuxsock)
# and, for TCP only, lmnetstrms + lmnsd_ptcp (plain TCP stream driver) and
# lmtcpclt (TCP sender). This is the set rsyslogd opened under qemu with
# device/rsyslog.conf forwarding over UDP and over TCP (no lmzlibw: only
# needed for omfwd compression, which the config does not use).
MODULES="imuxsock imklog imfile lmnet lmnetstrms lmnsd_ptcp lmtcpclt"

HOST_TRIPLE="${CROSS_TRIPLE:-armv7l-linux-musleabihf}"
PREFIX="$BUILD/prefix-rsyslog"
SRC="$BUILD/rsyslog-${RSYSLOG_VER}"
ESRC="$BUILD/libestr-${LIBESTR_VER}"
JSRC="$BUILD/libfastjson-${LIBFASTJSON_VER}"
ZSRC="$BUILD/zlib-${ZLIB_VER}"
BUNDLE="$OUT/rsyslog"

# Fresh trees every run so the script is rebuildable from scratch.
rm -rf "$SRC" "$ESRC" "$JSRC" "$ZSRC" "$PREFIX" "$BUNDLE"
mkdir -p "$PREFIX" "$BUNDLE"

RSYSLOG_TAR="$(fetch "$RSYSLOG_URL" "$RSYSLOG_SHA256")"
LIBESTR_TAR="$(fetch "$LIBESTR_URL" "$LIBESTR_SHA256")"
LIBFASTJSON_TAR="$(fetch "$LIBFASTJSON_URL" "$LIBFASTJSON_SHA256")"
ZLIB_TAR="$(fetch "$ZLIB_URL" "$ZLIB_SHA256")"

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# ---- zlib (shared, into prefix) -----------------------------------------------
tar -xzf "$ZLIB_TAR" -C "$BUILD"
(
  cd "$ZSRC"
  CC="$CCX" AR="${CROSS_TRIPLE}-ar" RANLIB="${CROSS_TRIPLE}-ranlib" \
    CFLAGS="$CFLAGS" \
    ./configure --shared --prefix="$PREFIX"
  make -j"$(nproc)" "libz.so.${ZLIB_VER}"
  make install
)

# ---- libestr (shared) -----------------------------------------------------------
tar -xzf "$LIBESTR_TAR" -C "$BUILD"
(
  cd "$ESRC"
  CC="$CCX" ./configure --host="$HOST_TRIPLE" --prefix="$PREFIX" \
    --enable-shared --disable-static --disable-testbench --disable-debug
  make -j"$(nproc)"
  make install
)

# ---- libfastjson (shared) -------------------------------------------------------
tar -xzf "$LIBFASTJSON_TAR" -C "$BUILD"
(
  cd "$JSRC"
  CC="$CCX" ./configure --host="$HOST_TRIPLE" --prefix="$PREFIX" \
    --enable-shared --disable-static --disable-rdrand
  make -j"$(nproc)"
  make install
)

# ---- rsyslog ----------------------------------------------------------------------
# Everything optional is off: no TLS, no crypto, no uuid, no systemd, no curl,
# no yaml, no man pages. Inputs imuxsock/imklog are default,
# imfile is enabled explicitly; omfwd is built in (--enable-inet).
# The atomics checks are run-tests that cannot run when cross compiling;
# ARMv7-A has 32- and 64-bit atomics (ldrex/strex, ldrexd/strexd).
# --disable-regexp does not compile in 8.2610.0 (template.c), so regexp stays
# on; it only builds lmregexp.so, which is not shipped.
tar -xzf "$RSYSLOG_TAR" -C "$BUILD"
(
  cd "$SRC"
  ap_cv_atomic_builtins=yes ap_cv_atomic_builtins_64=yes \
  CC="$CCX" \
  CPPFLAGS="-I$PREFIX/include" \
  LDFLAGS="-L$PREFIX/lib -Wl,-rpath-link,$PREFIX/lib $LDFLAGS" \
  ./configure \
    --host="$HOST_TRIPLE" \
    --prefix="$PREFIX" \
    --enable-shared --disable-static \
    --disable-silent-rules \
    --disable-Werror \
    --disable-debug \
    --disable-debug-symbols \
    --disable-testbench \
    --disable-default-tests \
    --disable-generate-man-pages \
    --disable-libyaml \
    --disable-fmhash \
    --disable-fmhttp \
    --disable-mmleefparse \
    --disable-libcap-ng \
    --disable-uuid \
    --disable-libgcrypt \
    --disable-libzstd \
    --disable-libsystemd \
    --disable-imjournal \
    --disable-gnutls \
    --disable-openssl \
    --disable-mbedtls \
    --disable-liblogging-stdlog \
    --disable-kmsg \
    --enable-klog \
    --disable-impstats-push \
    --enable-imfile
  make -j"$(nproc)"
  make install
)

# ---- bundle -------------------------------------------------------------------------
TCLIB="$(dirname "$("$CC" -print-file-name=libc.so)")"
cp -L "$TCLIB/libc.so" "$BUNDLE/ld-musl-armhf.so.1"
cp "$PREFIX/sbin/rsyslogd" "$BUNDLE/rsyslogd"
for m in $MODULES; do
  cp "$PREFIX/lib/rsyslog/$m.so" "$BUNDLE/$m.so"
done

# Shared libraries under their SONAME (vfat has no symlinks), found from the
# NEEDED entries of everything in the bundle. libc.so is the loader itself.
for need in $("${CROSS_TRIPLE}-readelf" -d "$BUNDLE"/rsyslogd "$BUNDLE"/*.so \
              | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u); do
  [ "$need" = libc.so ] && continue
  cp -L "$PREFIX/lib/$need" "$BUNDLE/$need"
done

"${STRIP:-strip}" -s "$BUNDLE/rsyslogd"
"${STRIP:-strip}" --strip-unneeded "$BUNDLE"/*.so* "$BUNDLE/ld-musl-armhf.so.1"
chmod 0755 "$BUNDLE"/*

echo "---- build summary ----"
file "$BUNDLE"/*
"${CROSS_TRIPLE}-readelf" -d "$BUNDLE"/rsyslogd "$BUNDLE"/*.so* | grep -E '^File:|NEEDED' || true
echo "rsyslog version: ${RSYSLOG_VER} (${RSYSLOG_URL})"
echo "rsyslog tarball sha256: ${RSYSLOG_SHA256}"
echo "libestr version: ${LIBESTR_VER} (${LIBESTR_URL})"
echo "libestr tarball sha256: ${LIBESTR_SHA256}"
echo "libfastjson version: ${LIBFASTJSON_VER} (${LIBFASTJSON_URL})"
echo "libfastjson tarball sha256: ${LIBFASTJSON_SHA256}"
echo "zlib version: ${ZLIB_VER} (${ZLIB_URL})"
echo "zlib tarball sha256: ${ZLIB_SHA256}"
echo "output: $BUNDLE/"
for f in "$BUNDLE"/*; do
  echo "  $(basename "$f")  $(stat -c %s "$f") bytes  sha256 $(sha256sum "$f" | cut -d' ' -f1)"
done
echo "bundle size: $(cat "$BUNDLE"/* | wc -c) bytes"
