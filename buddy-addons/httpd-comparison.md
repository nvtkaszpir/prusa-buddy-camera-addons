# HTTP/HTTPS file server for the camera: comparison

Goal: serve a directory listing of `/mnt/sdcard` over HTTP and HTTPS, so a host can mirror the card with `wget --mirror` or curl. Constraints from the target ([README.md, Target facts](README.md#target-facts)): ARMv7 hard-float, 34 MB RAM with about 6 MB free, no device libc to rely on (static musl binaries), no `openssl` on the device, config should be a plain file that can be replaced over scp or on the card.

The camera's own BusyBox 1.27.2 has no `httpd` applet (`strings downloads/3/dump/bin/busybox` lists `telnetd`, `tftp`, `ssl_client`, but no `httpd`), so every option means shipping a new binary.

What matters for `wget --mirror`: the listing must contain only links to entries. Apache-style sort links (`?C=N;O=D`) or `?sort=...` links are crawled as extra URLs and produce duplicate copies of each directory page. Inline CSS/JS does no harm to wget, but is noise for curl.

## Table

Sizes and RSS are for 32-bit ARM. "measured" means built or downloaded here; everything else is an estimate.

| server | TLS built in (library) | directory listing | config | static musl build | binary / RSS | license | latest release |
|---|---|---|---|---|---|---|---|
| lighttpd 1.4.x | yes: mod_mbedtls, mod_wolfssl, mod_openssl, mod_gnutls [1] | plain HTML table; inline CSS+JS only with `auto-layout` on; no sort links in the HTML [2][3] | file (`lighttpd.conf`) | yes, autotools `LIGHTTPD_STATIC=yes` + custom `src/plugin-static.h` [4]; meson/cmake static builds in 1.4.85 still build mod_mbedtls as a shared module | 1,161,028 B measured (1.4.85 + mbedTLS 3.6.7 + PCRE2 10.49, `out/lighttpd`) / estimate 1-2 MB | BSD-3-Clause | 1.4.85, 2026-07 [5] |
| nginx | yes: OpenSSL API only (also LibreSSL, BoringSSL) [6] | `autoindex`: `<pre>` list, no CSS/JS, no sort links [7] | file | yes, but OpenSSL is the bulk | estimate 3-5 MB with OpenSSL / estimate 2-4 MB (master + worker) | BSD-2-Clause | 1.31.8 / 1.30.6, 2026-10 [8] |
| mini_httpd | yes: OpenSSL (`SSLv23_server_method`) [9] | `<pre>` list, no CSS/JS | CLI + `-C` file [10] | yes | estimate 2-3 MB with OpenSSL; forks per connection | BSD-2-Clause | 1.30, 2018 [10] |
| thttpd | no [11] | plain HTML list | CLI + `-C` file | yes | estimate ~100 KB | BSD-2-Clause | 2.29, 2018 [11] |
| darkhttpd | no (no TLS code in `darkhttpd.c`) [12] | `<pre>` list, no CSS/JS | CLI only [12] | yes, single C file | 99,660 B measured (this toolchain, `-Os`, stripped) / estimate <0.5 MB | ISC | 1.17, 2025-07 [12] |
| busybox httpd | no (no TLS code in `httpd.c`) [13] | only through a separate `index.cgi` (`httpd_indexcgi.c`), with inline CSS [14] | CLI + `httpd.conf` | yes | estimate 100-200 KB for a minimal busybox | GPL-2.0 | 1.37.0, 2024 (1.38.0 unstable, 2026) [15] |
| civetweb | yes: OpenSSL, mbedTLS, or GnuTLS [16] | sort links `?n` `?d` `?s` in the header row [16] | file or CLI | yes | estimate 0.5-1 MB plus TLS library | MIT | 1.16, 2023 [17] |
| mongoose | yes: own TLS 1.3, or mbedTLS / OpenSSL [18] | `listdir` returns JSON, not HTML [19]; wget cannot crawl it | none: a library, you write `main()` | yes | estimate 0.2-0.5 MB | GPL-2.0 or commercial [18] | 7.23, 2026-08 [20] |
| Hiawatha | yes: bundled mbedTLS [21] | `ShowIndex` needs XSLT (libxml2 + libxslt); default `index.xslt` has inline CSS and JS [22] | file | possible, needs libxml2 + libxslt static | estimate 2-4 MB | GPL-2.0 | 12.4, 2026-09 [21] |
| uhttpd (OpenWrt) | via ustream-ssl (mbedTLS / wolfSSL / OpenSSL), loaded with `dlopen()` [23] | plain `<ol>` list [23] | CLI (UCI is an OpenWrt init script) | not as-is: TLS is a `dlopen`ed `.so`; needs libubox | estimate 100-200 KB without TLS | ISC | no releases; git, 2026-10 [23] |
| Caddy | yes: Go `crypto/tls` | `browse`: inline CSS/JS and `?sort=name&order=asc` links [24] | file (Caddyfile) | yes (Go) | 48,562,338 B measured (official `linux_armv7`, v2.11.7) [25]; larger than device RAM | Apache-2.0 | 2.11.7, 2026-10 [25] |
| Go `net/http` FileServer (minimal program) | yes: Go `crypto/tls` | `<pre>` list, no CSS/JS, no sort links | whatever you write | yes, `CGO_ENABLED=0` | 6,291,616 B measured (go1.27.1, `GOARM=7`, `-s -w`) / estimate 5-10 MB | BSD-3-Clause | n/a |
| stunnel + TLS-less server | stunnel: OpenSSL only [26] | from the backend server | file | yes | estimate 2-3 MB for stunnel + OpenSSL, plus the backend; two processes | GPL-2.0+ with OpenSSL exception [26] | 5.82, 2026-09 [26] |
| hitch + TLS-less server | hitch: OpenSSL (`libssl`, `libcrypto`) + libev [27] | from the backend server | file or CLI | yes | estimate 2-3 MB plus the backend; two processes | BSD-2-Clause | 1.8.0, 2023-08 [27] |

## Notes

- Without a TLS terminator, thttpd, darkhttpd and busybox httpd only cover HTTP. Adding stunnel or hitch brings in OpenSSL (several MB static) and a second process to start, watch and log. That is more moving parts than one server with TLS built in.
- mini_httpd serves either HTTP or HTTPS per process (`-S`), so both need two processes. thttpd and mini_httpd have had no release since 2018.
- civetweb and Caddy put sort links in the listing, which `wget --mirror` follows (wget's `--reject-regex` can work around it, but every client would need it). Caddy is also too large for 34 MB of RAM.
- Mongoose's current file server answers directory requests with JSON, so the host would need its own crawler.
- Hiawatha is maintained and uses mbedTLS, but listings need libxml2 + libxslt in the static build and a custom XSLT to drop the CSS/JS.
- nginx gives the plainest listing, but it only supports OpenSSL-API libraries, so the static binary is several times larger, and the device has no tool to make a certificate unless OpenSSL's CLI is shipped too.
- A small Go program would work, but its runtime would likely use most of the ~6 MB of free RAM (estimate).

## Choice: lighttpd 1.4.x + mbedTLS 3.6 LTS

Checked against the lighttpd docs and `src/mod_dirlisting.c` (1.4.85):

- `dir-listing.auto-layout = "disable"` drops everything from `<!DOCTYPE` to `<body>` and `</body></html>` [2]. In the source, the inline `<style>` block, the footer and the inline sort `<script>` are only written when auto-layout is on [3]. The output starts at `<h2>Index of /path</h2>` followed by a plain `<table>`. It is an HTML fragment, which wget and curl handle.
- The deployed config keeps auto-layout disabled and inserts a static header with an inline `<style>` via `dir-listing.show-header` + `dir-listing.encode-header = "disable"`, which styles the table for browsers without JavaScript, sort links or external files.
- Sorting: the column headers are plain `<th>Name</th>` etc. with no links [3]. Sorting in the browser is done by the inline JS, which is not sent with auto-layout off. Correction to the original note: lighttpd does accept Apache-style `?C=N&O=D` query arguments to set the initial sort order [2], but it never writes such links into the page, so wget never sees them. Server-side alphabetical sorting is on by default (`dir-listing.sort`, since 1.4.74) [2].
- A `?json` query returns JSON (since 1.4.72) [2]. No link to it is emitted either.
- `dir-listing.hide-dotfiles` defaults to enable [2]. With auto-layout off the response is `Content-Type: text/html` with no charset unless `dir-listing.encoding` is set (the wiki's `iso-8859-1` default does not match the source) [3], so set `dir-listing.encoding = "utf-8"`.
- HTTP and HTTPS from one process: a global `server.port` plus `$SERVER["socket"] == ":8443" { ssl.engine = "enable" ... }` [1]. `ssl.pemfile` and `ssl.privkey` can be separate `.crt` and `.key` files [1]. There is no separate mod_mbedtls wiki page; TLS modules are documented on Docs_SSL [1].
- TLS versions: lighttpd 1.4.85 accepts TLS 1.3 only by default. Clients that need TLS 1.2 require `ssl.openssl.ssl-conf-cmd = ("MinProtocol" => "TLSv1.2")` (checked under qemu).
- One binary: the autotools static-plugin build (`LIGHTTPD_STATIC=yes` with the modules listed in `src/plugin-static.h`) links the modules, including mod_mbedtls, into `lighttpd` with no `dlopen` [4]. The meson `build_static` and cmake static builds in 1.4.85 still build mod_mbedtls as a separate shared module, so `build-lighttpd.sh` does not use them. lighttpd 1.4.85 builds against mbedTLS 3.6 and 4.x (NEWS has the 4.x port) [5].
- mbedTLS keeps the binary small: `out/lighttpd` is 1,161,028 B with mbedTLS 3.6.7 and PCRE2 linked in (measured). Its `gen_key` and `cert_write` sample programs, shipped as `mbedtls-gen-key` (173,316 B) and `mbedtls-cert-write` (255,236 B), create the ECDSA key and self-signed certificate on the device, which has no `openssl`.

Caveat on the mbedTLS branch: 3.6 LTS is supported until March 2027; 4.1 LTS until March 2029 [28]. mbedTLS 4.x has no `programs/pkey/gen_key.c` any more (`programs/x509/cert_write.c` is still there) [29], so moving to 4.x later means writing a small PSA key generator or generating the key on the host. For now 3.6.7 (2026-07) [28] is the choice that keeps on-device key generation working.

## Sources

[1]: https://redmine.lighttpd.net/projects/lighttpd/wiki/Docs_SSL
[2]: https://redmine.lighttpd.net/projects/lighttpd/wiki/Mod_dirlisting
[3]: https://github.com/lighttpd/lighttpd1.4/blob/master/src/mod_dirlisting.c (`http_list_directory_header`, `http_list_directory_footer`, `mod_dirlisting_content_type`)
[4]: `build-lighttpd.sh` (header comment and build steps) and https://github.com/lighttpd/lighttpd1.4/blob/master/INSTALL (static build)
[5]: https://github.com/lighttpd/lighttpd1.4/blob/master/NEWS
[6]: https://github.com/nginx/nginx/blob/master/auto/options (`--with-openssl`)
[7]: https://github.com/nginx/nginx/blob/master/src/http/modules/ngx_http_autoindex_module.c
[8]: https://github.com/nginx/nginx/releases
[9]: https://acme.com/software/mini_httpd/mini_httpd-1.30.tar.gz (`mini_httpd.c`)
[10]: https://acme.com/software/mini_httpd/
[11]: https://acme.com/software/thttpd/
[12]: https://github.com/emikulic/darkhttpd (README, `darkhttpd.c`, releases)
[13]: https://github.com/mirror/busybox/blob/master/networking/httpd.c
[14]: https://github.com/mirror/busybox/blob/master/networking/httpd_indexcgi.c
[15]: https://busybox.net/
[16]: https://github.com/civetweb/civetweb/blob/master/src/civetweb.c (`USE_MBEDTLS`, `USE_GNUTLS`, directory listing header)
[17]: https://github.com/civetweb/civetweb/releases
[18]: https://github.com/cesanta/mongoose/blob/master/README.md
[19]: https://github.com/cesanta/mongoose/blob/master/mongoose.c (`listdir`)
[20]: https://github.com/cesanta/mongoose/releases
[21]: https://gitlab.com/hsleisink/hiawatha/-/blob/master/ChangeLog
[22]: https://gitlab.com/hsleisink/hiawatha/-/blob/master/man/hiawatha.1.in (`ShowIndex`), https://gitlab.com/hsleisink/hiawatha/-/blob/master/config/index.xslt
[23]: https://git.openwrt.org/?p=project/uhttpd.git (`tls.c`, `file.c`)
[24]: https://github.com/caddyserver/caddy/blob/master/modules/caddyhttp/fileserver/browse.html
[25]: https://github.com/caddyserver/caddy/releases/tag/v2.11.7
[26]: https://www.stunnel.org/ and https://www.stunnel.org/NEWS.html
[27]: https://github.com/varnish/hitch (`configure.ac`, `CHANGES.rst`)
[28]: https://github.com/Mbed-TLS/mbedtls/blob/development/BRANCHES.md and https://github.com/Mbed-TLS/mbedtls/releases
[29]: https://github.com/Mbed-TLS/mbedtls/tree/mbedtls-4.1.1/programs
