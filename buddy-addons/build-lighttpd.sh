#!/usr/bin/env bash
# Build a static, stripped lighttpd 1.4.x with mbedTLS (HTTP + HTTPS) and the
# mbedTLS key/certificate tools for the Prusa/Buddy3D camera (ARMv7l, musl).
# Outputs:
#   buddy-addons/out/lighttpd             web server, modules compiled in
#   buddy-addons/out/mbedtls-gen-key      mbedTLS programs/pkey/gen_key
#   buddy-addons/out/mbedtls-cert-write   mbedTLS programs/x509/cert_write
#
# lighttpd is built with autotools in its static-plugin mode
# (LIGHTTPD_STATIC=yes + src/plugin-static.h): there is no dlopen, so only the
# modules listed in LIGHTTPD_MODULES below can appear in server.modules.
# meson/cmake static builds are not used because they still build mod_mbedtls
# as a separate shared module instead of linking it into the binary.
#
# PCRE2 (no JIT) is linked in so $HTTP["url"] =~ "..." regex conditionals work
# (needed to deny dot-directories at any depth). No zlib/zstd/brotli/bzip2,
# lua, webdav, ldap, dbi, xattr, fam.
set -euo pipefail

source "$(dirname "$0")/env.sh"
toolchain_init "$@"

# Toolchain defaults to PIE; the device requires a plain static ET_EXEC.
export CFLAGS="$CFLAGS -fno-pie"
export LDFLAGS="$LDFLAGS -no-pie"

LIGHTTPD_VER=1.4.85
LIGHTTPD_URL="https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-${LIGHTTPD_VER}.tar.xz"
# from lighttpd-1.4.85.sha256sum next to the tarball
LIGHTTPD_SHA256=18de51b393bac4a6827879e1a7ff377c169e414bae92cd245091d80fc2601d13

MBEDTLS_VER=3.6.7
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VER}/mbedtls-${MBEDTLS_VER}.tar.bz2"
# from the mbedtls-3.6.7 release notes / mbedtls-3.6.7-sha256sum.txt
MBEDTLS_SHA256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6

PCRE2_VER=10.49
PCRE2_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.bz2"
# GitHub release asset digest; tarball also GPG-verified (Nicholas Wilson,
# A9553620 4A3BB489 71523128 2A98E77E B6F24CA8)
PCRE2_SHA256=53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384

# Modules compiled into lighttpd. mod_h2 lives in h2.c (always built) and
# mod_mbedtls.c is added by --with-mbedtls; the rest are the .c files below.
LIGHTTPD_MODULES="mod_access mod_accesslog mod_alias mod_auth mod_authn_file
  mod_dirlisting mod_h2 mod_indexfile mod_mbedtls mod_redirect mod_rewrite
  mod_setenv mod_staticfile"
LIGHTTPD_MOD_SRCS="mod_access.c mod_accesslog.c mod_alias.c mod_auth.c
  mod_auth_api.c mod_authn_file.c mod_dirlisting.c mod_indexfile.c
  mod_redirect.c mod_rewrite.c mod_setenv.c mod_staticfile.c"

PREFIX="$BUILD/prefix-lighttpd"
SRC="$BUILD/lighttpd-${LIGHTTPD_VER}"
MSRC="$BUILD/mbedtls-${MBEDTLS_VER}"
PSRC="$BUILD/pcre2-${PCRE2_VER}"

# Fresh trees every run so the script is rebuildable from scratch.
rm -rf "$SRC" "$MSRC" "$PSRC" "$PREFIX"
mkdir -p "$PREFIX/include" "$PREFIX/lib"

LIGHTTPD_TAR="$(fetch "$LIGHTTPD_URL" "$LIGHTTPD_SHA256")"
MBEDTLS_TAR="$(fetch "$MBEDTLS_URL" "$MBEDTLS_SHA256")"
PCRE2_TAR="$(fetch "$PCRE2_URL" "$PCRE2_SHA256")"

# Keep host pkg-config files out of the cross build.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""

# ---- mbedTLS (static libs into prefix + gen_key/cert_write) -----------------
# Default config: TLS 1.2 + 1.3, ECDHE-ECDSA/ECDHE-RSA suites, AES-GCM,
# ChaCha20-Poly1305, X.509 write support for cert_write.
tar -xjf "$MBEDTLS_TAR" -C "$BUILD"
(
  cd "$MSRC"
  make -C library -j"$(nproc)" CC="$CC" AR="$AR" CFLAGS="$CFLAGS" static
  make -C programs -j"$(nproc)" CC="$CC" AR="$AR" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    pkey/gen_key x509/cert_write
  cp -a include/mbedtls include/psa "$PREFIX/include/"
  cp library/libmbedcrypto.a library/libmbedx509.a library/libmbedtls.a "$PREFIX/lib/"
)

# ---- PCRE2 (static libpcre2-8 into prefix, no JIT) --------------------------
tar -xjf "$PCRE2_TAR" -C "$BUILD"
(
  cd "$PSRC"
  ./configure \
    --host="$CROSS_TRIPLE" \
    --prefix="$PREFIX" \
    --disable-shared \
    --enable-static \
    --enable-pcre2-8 \
    --disable-pcre2-16 \
    --disable-pcre2-32 \
    --disable-jit \
    --disable-pcre2grep-libz \
    --disable-pcre2grep-libbz2 \
    --disable-pcre2test-libreadline
  make -j"$(nproc)" libpcre2-8.la
  make install-libLTLIBRARIES install-nodist_includeHEADERS
)

# ---- lighttpd (static, modules compiled in) ---------------------------------
tar -xJf "$LIGHTTPD_TAR" -C "$BUILD"
(
  cd "$SRC"

  # Static-plugin build, per lighttpd's INSTALL: list the module sources in
  # the "if LIGHTTPD_STATIC" lighttpd_SOURCES of src/Makefile.am and name the
  # modules in src/plugin-static.h.
  awk -v srcs="$LIGHTTPD_MOD_SRCS" '
    /^if LIGHTTPD_STATIC$/ { st = 1 }
    st == 1 && /^lighttpd_SOURCES = \\$/ {
      print; print "  $(src) \\"
      n = split(srcs, m, /[ \n]+/); k = 0
      for (i = 1; i <= n; i++) if (m[i] != "") s[++k] = m[i]
      for (i = 1; i <= k; i++) print "  " s[i] (i < k ? " \\" : "")
      skip = 1; next
    }
    skip && /^  mod_webdav\.c$/ { skip = 0; st = 2; next }
    skip { next }
    { print }
  ' src/Makefile.am > src/Makefile.am.new
  mv src/Makefile.am.new src/Makefile.am
  if grep -qx '  mod_webdav.c' src/Makefile.am; then
    echo "src/Makefile.am static module list not patched" >&2; exit 1
  fi
  for m in $LIGHTTPD_MODULES; do echo "PLUGIN_INIT($m)"; done > src/plugin-static.h

  ./autogen.sh

  LIGHTTPD_STATIC=yes \
  CC_FOR_BUILD=cc CPP_FOR_BUILD="cc -E" \
  CPPFLAGS="-I$PREFIX/include" \
  LDFLAGS="-L$PREFIX/lib $LDFLAGS" \
  ./configure \
    --host="$CROSS_TRIPLE" \
    --prefix=/usr \
    --enable-static \
    --disable-shared \
    --with-mbedtls="$PREFIX" \
    --with-pcre2="$PREFIX" \
    --without-zlib \
    --without-zstd \
    --without-bzip2 \
    --without-brotli \
    --without-libdeflate \
    --without-lua \
    --without-webdav-props \
    --without-webdav-locks \
    --without-ldap \
    --without-dbi \
    --without-attr \
    --without-fam \
    --without-xxhash \
    --without-maxminddb
  # -all-static makes libtool pass -static to the final link. The upstream
  # -export-dynamic is only for dlopen()ed modules, which a static build has
  # none of. Only the lighttpd target is built: src/t/test_mod (a noinst
  # unit-test program in "all") does not compile against a custom
  # plugin-static.h. BUILT_SOURCES (lemon parsers, versionstamp.h) first.
  make -C src parsers versionstamp
  make -C src -j"$(nproc)" lighttpd lighttpd_LDFLAGS="-all-static"
)

# ---- output -----------------------------------------------------------------
"${STRIP}" -s -o "$OUT/lighttpd" "$SRC/src/lighttpd"
"${STRIP}" -s -o "$OUT/mbedtls-gen-key" "$MSRC/programs/pkey/gen_key"
"${STRIP}" -s -o "$OUT/mbedtls-cert-write" "$MSRC/programs/x509/cert_write"
chmod 0755 "$OUT/lighttpd" "$OUT/mbedtls-gen-key" "$OUT/mbedtls-cert-write"

echo "---- build summary ----"
file "$OUT/lighttpd" "$OUT/mbedtls-gen-key" "$OUT/mbedtls-cert-write"
echo "lighttpd version: ${LIGHTTPD_VER} (${LIGHTTPD_URL})"
echo "lighttpd tarball sha256: ${LIGHTTPD_SHA256}"
echo "lighttpd static modules:" $LIGHTTPD_MODULES
echo "mbedtls version: ${MBEDTLS_VER} (${MBEDTLS_URL})"
echo "mbedtls tarball sha256: ${MBEDTLS_SHA256}"
echo "pcre2 version: ${PCRE2_VER} (${PCRE2_URL})"
echo "pcre2 tarball sha256: ${PCRE2_SHA256}"
for f in lighttpd mbedtls-gen-key mbedtls-cert-write; do
  echo "output: $OUT/$f"
  echo "output sha256: $(sha256sum "$OUT/$f" | cut -d' ' -f1)"
  echo "output size: $(stat -c %s "$OUT/$f") bytes"
done
