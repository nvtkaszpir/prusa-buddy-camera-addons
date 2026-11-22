# lighttpd (HTTP/HTTPS file server)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile), [Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet).

A read-only web server for the microSD card, so files (for example timelapses) can be fetched with a browser, `wget` or `curl`. Why lighttpd: [httpd-comparison.md](httpd-comparison.md) compares the candidates; lighttpd with mbedTLS serves HTTP and HTTPS from one small static binary with TLS built in, a plain directory listing table styled only by the inline `<style>` from `dirlisting-header.html` (no JavaScript, no sort links), and on-device key and certificate generation, with no TLS terminator or second process.

## Artifacts

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/lighttpd` | lighttpd 1.4.85 + mbedTLS 3.6.7 + PCRE2 10.49 (no JIT), `build-lighttpd.sh` | read-only HTTP/HTTPS file server, modules linked in statically | 1161028 B | `022f039a4a3a5e81127a1b5dbbb75c3eec31848d78e04c11bb8ba9e167b3952f` |
| `out/mbedtls-gen-key` | mbedTLS 3.6.7, `build-lighttpd.sh` | key generator, used for the TLS key on first start | 173316 B | `267f33a428f528a91f721e8421732d97521ec8241ec41b427c6fa93083a665fa` |
| `out/mbedtls-cert-write` | mbedTLS 3.6.7, `build-lighttpd.sh` | certificate writer, used for the self-signed cert on first start | 255236 B | `9d1c71381d0dfeaf05ff46ff6c80dafecb4c26555405f31c498fa56858929a6e` |

```sh
./build-lighttpd.sh     # -> out/lighttpd, out/mbedtls-gen-key, out/mbedtls-cert-write
qemu-arm-static out/lighttpd -v                   # lighttpd/1.4.85 (ssl) - a light and fast webserver
```

## What it serves

- HTTP on port 8080, HTTPS on port 8443. TLS 1.2 and 1.3 are accepted. lighttpd 1.4.85 defaults to TLS 1.3 only; the config adds `MinProtocol TLSv1.2`.
- Document root: `/mnt/sdcard`.
- Directory listing: a plain HTML table, no JavaScript, no sort links, so `wget --mirror` fetches no duplicates. Listings are shown even if a directory contains `index.html`.
- Listing look: lighttpd's auto-layout stays off; the table is styled by an inline `<style>` in `dirlisting-header.html`, which lighttpd inserts before each listing. Light and dark theme follow the browser setting. No JavaScript, no sort links and no external files (CSS, fonts, images), so wget and curl see only the entry links.
- Listing title: the page `<title>` (browser tab) and a heading above "Index of ..." show the camera's short host name, with its full DNS name next to the heading, for example `buddy-cam-1` and `buddy-cam-1.intra.hlds.pl`. See [Listing title](#listing-title).
- Dotfiles and dot-directories are hidden and denied (403) at any depth.
- `rclone.conf`, `htpasswd`, `*.key`, `*.pem` and `authorized_keys` are denied (403) and hidden from listings.
- The card's `/userdata/` directory is denied (403) and hidden from listings. It holds copies of the camera's `/userdata/*` made by `lp_app.sh` at every boot, including `xhr_config.ini` (Prusa Connect token and Wi-Fi AP password) and `xhr_http_token.conf`.
- `sdcard_cfg.txt` and `sdcard_cfg_applied.txt` are denied (403) and hidden from listings. lp_app 3.1.6 and later
  reads `/mnt/sdcard/sdcard_cfg.txt` at start (keys `token`, `ssid`, `pwd`, as in the setup QR code), applies it
  and renames it to `sdcard_cfg_applied.txt`, which stays on the card with the Prusa Connect token and Wi-Fi
  password in clear text.
- URL matching is case-insensitive, as on vfat, so `/RCLONE.CONF` is denied too.
- Read-only: only GET and HEAD. No webdav, cgi or proxy modules are compiled in.
- HTTP basic auth on every URL, on both ports (realm `camera`, `require valid-user`). Users and password hashes are read from `/userdata/httpd/htpasswd`, which `start-httpd.sh` copies from the card's `/mnt/sdcard/bin/htpasswd`. Without that file every request gets 401. A successful login is remembered for 10 minutes (`auth.cache` with `max-age` 600), so `wget --mirror` does not pay the hash cost on every request. See [Users and passwords](#users-and-passwords).
- Basic auth over plain HTTP (port 8080) sends the password readable on the network. Prefer HTTPS, or disable plain HTTP (see [HTTPS only or HTTP only](#https-only-or-http-only)). The self-signed certificate only encrypts the transfer.
- To turn auth off, delete the `auth.*` lines from `lighttpd.conf`. Then anyone who can reach ports 8080/8443 can read everything on the card that is not denied above.

Compiled-in modules (only these can appear in `server.modules`): `mod_access`, `mod_accesslog`, `mod_alias`, `mod_auth`, `mod_authn_file`, `mod_dirlisting`, `mod_h2`, `mod_indexfile`, `mod_mbedtls`, `mod_redirect`, `mod_rewrite`, `mod_setenv`, `mod_staticfile`. The build uses autotools static-plugin mode (`LIGHTTPD_STATIC=yes` with a custom `src/plugin-static.h`).

## Install on the card

Layout on the card:

```
/mnt/sdcard/bin/lighttpd            <- out/lighttpd
/mnt/sdcard/bin/mbedtls-gen-key     <- out/mbedtls-gen-key
/mnt/sdcard/bin/mbedtls-cert-write  <- out/mbedtls-cert-write
/mnt/sdcard/bin/start-httpd.sh      <- device/start-httpd.sh
/mnt/sdcard/bin/lighttpd.conf       <- device/lighttpd.conf (edit as needed)
/mnt/sdcard/bin/dirlisting-header.html <- device/dirlisting-header.html (optional, listing style)
/mnt/sdcard/bin/htpasswd            <- secrets/htpasswd (from gen-htpasswd.sh)
/mnt/sdcard/lp_app.sh               <- your existing hook, with device/httpd-hook.sh pasted in
```

Create the password file first (see [Users and passwords](#users-and-passwords)):

```sh
./gen-htpasswd.sh USER                  # -> secrets/htpasswd
```

```sh
SD=/path/to/mounted/sdcard
mkdir -p "$SD/bin"
cp out/lighttpd out/mbedtls-gen-key out/mbedtls-cert-write device/start-httpd.sh device/lighttpd.conf device/dirlisting-header.html "$SD/bin/"
cp secrets/htpasswd "$SD/bin/htpasswd"
sync
```

`dirlisting-header.html` is optional. Without it, listings still work, unstyled and without a title. For the DNS name in the title, also put `out/drill` on the card (`cp out/drill "$SD/bin/"`). `start-httpd.sh` installs it itself, so the ssh add-on is not needed for this (see [drill.md](drill.md)).

Copy `device/httpd-hook.sh` into `lp_app.sh` right **after** the line

```sh
mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
```

and before `/tmp/sync_loop.sh`, which never returns. This differs from the ssh block, which goes before `umount` (see [Install via microSD](README.md#install-via-microsd)). lighttpd serves the card, so it must start on the final mount. It runs with cwd `/` and logs to `/tmp`, so it holds only the files being served open on the card.

## What happens at boot

The hook runs `start-httpd.sh`, which:
1. copies `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write` and `drill` (if present on the card) to `/userdata/bin/` when their md5 differs from the card's;
2. creates `/userdata/httpd/` with mode 700;
3. on first start, generates `/userdata/httpd/server.key` (ECDSA P-256) and `/userdata/httpd/server.crt` (self-signed, CN and SAN `DNS:` set to the camera's hostname). The certificate is valid for 10 years: not_before is 1 hour before the current UTC time (so clients whose clocks lag slightly don't see "not yet valid"), and not_after is the same date and time 10 years after not_before (29 February maps to 28 February). If the camera clock is before 2025 (RTC not set), it uses 2025-01-01 00:00:00 UTC as the start instead, valid to 2035-01-01, and logs a warning suggesting to delete `server.key` and `server.crt` and rerun `start-httpd.sh` once the clock is right. It logs `generated self-signed certificate /userdata/httpd/server.crt for CN=<cn>, valid <not_before> to <not_after> (UTC)`. Delete both files to get a new certificate on the next start;
4. if `/mnt/sdcard/bin/lighttpd.conf` differs from `/userdata/httpd/lighttpd.conf`, checks it with `lighttpd -tt` and installs it only if the check passes (the card wins);
5. checks the installed config with `lighttpd -tt` before touching a running server;
6. copies `dirlisting-header.html` to `/userdata/httpd/dirlisting-header.tmpl` when it differs, and writes `/userdata/httpd/dirlisting-header.html` from it with the title filled in (see [Listing title](#listing-title)). No restart; lighttpd reads the header for every listing;
7. copies `/mnt/sdcard/bin/htpasswd` to `/userdata/httpd/htpasswd` (mode 600) when its md5 differs (the card wins), logs `installed htpasswd (md5 ...)` and restarts lighttpd so the login cache is dropped. If the config uses an htpasswd userfile and `/userdata/httpd/htpasswd` is missing or empty, it logs `WARNING: no /userdata/httpd/htpasswd (copy one to /mnt/sdcard/bin/htpasswd); every request will get 401`;
8. starts lighttpd if it is not running. A running server is restarted only when the binary, the config or `htpasswd` changed, or with the `restart` argument; otherwise the script does nothing.

Logs:
- `/mnt/sdcard/logs/httpd.log` (or `/tmp/httpd.log` if the logs dir is missing): the steps of `start-httpd.sh`, including rejected configs and the `lighttpd -tt` output.
- `/tmp/lighttpd.log`: the server's error log. There is no access log. Lost on reboot.
- `/tmp/lighttpd.pid`: the pid file.

## Launch manually

Via the start script:

```sh
sh /mnt/sdcard/bin/start-httpd.sh            # install/refresh, start if not running
sh /mnt/sdcard/bin/start-httpd.sh restart    # always restart a running server
sh /mnt/sdcard/bin/start-httpd.sh stop       # stop the server
```

Directly, in the foreground, for debugging (stop the background server first):

```sh
/userdata/bin/lighttpd -D -f /userdata/httpd/lighttpd.conf
```

Config check:

```sh
/userdata/bin/lighttpd -tt -f /userdata/httpd/lighttpd.conf
```

To restart the whole camera, see [Rebooting](README.md#rebooting).

## Edit the config

Edit `device/lighttpd.conf` (or a copy), upload it to the card and rerun the start script (or reboot):

```sh
scp -O lighttpd.conf root@CAMERA_IP:/mnt/sdcard/bin/
ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-httpd.sh
```

The script checks the new config with `lighttpd -tt`. If the check fails, the config is rejected, the installed one is kept, the running server is not stopped, and the script exits with status 1. The reason is written to `/mnt/sdcard/logs/httpd.log` after a `REJECTED` line. If the check passes, the config is installed and the server restarted.

The listing style is edited the same way: upload `/mnt/sdcard/bin/dirlisting-header.html` and rerun the start script. No restart is needed after `start-httpd.sh` copies it. It must not reference external files (no `<link>`, `<script src>`, images, fonts or CSS `url()`), or `wget --mirror` would fetch them.

## Listing title

`dirlisting-header.html` is a template with two placeholders, `@HOSTNAME@` and `@FQDN@`. The default uses them in `<title>@HOSTNAME@</title>` and in `<header class="cam"><h1>@HOSTNAME@</h1><span>@FQDN@</span></header>` above lighttpd's "Index of ..." heading. `start-httpd.sh` fills them in:

- The full name comes from DNS: the PTR record of the camera's first non-loopback IPv4 address (from `ifconfig`), looked up with `/userdata/bin/drill -x`. `@FQDN@` becomes that name (for example `buddy-cam-1.intra.hlds.pl`), and `@HOSTNAME@` the part before the first dot (`buddy-cam-1`). The lookup in the start script itself gives up after 5 s (busybox `timeout -t 5`), so a DNS server that does not answer cannot hold up boot.
- Until DNS answers, `@HOSTNAME@` is the output of `hostname` (`Rockchip` on this camera) and `@FQDN@` is empty (the CSS hides the empty span).
- At boot the network is usually not up yet when the hook runs, because lp_app brings up Wi-Fi later. In that case `start-httpd.sh` starts a background job that retries the lookup every 15 s for up to 10 minutes, then rewrites the header. Its pid is in `/tmp/httpd-title.pid`, and only one such job runs at a time. When a later run of `start-httpd.sh` gets the name right away, it stops that job. The job keeps nothing open on the card.
- Without `drill` (on the card or in `/userdata/bin`), the title stays the `hostname` output.
- `httpd.log` shows which name was used: `listing title: <name> (reverse DNS)`, `... for now; retrying reverse DNS in the background`, or `... (no /userdata/bin/drill for reverse DNS)`.

The name is not refreshed if the IP address changes later; rerun `start-httpd.sh` for that. To use a fixed title, write it into the template instead of the placeholders.

## HTTPS only or HTTP only

By default one lighttpd process serves plain HTTP on 8080 and HTTPS on 8443. To keep only one of them, edit `lighttpd.conf` as below, then upload it and rerun the start script as in [Edit the config](#edit-the-config). The same instructions are in the comments of the config's "ports" section.

**HTTPS only** (no plain HTTP, recommended with basic auth): replace the line `server.port = 8080` with

```
server.port = 8443
ssl.engine  = "enable"
ssl.pemfile = "/userdata/httpd/server.crt"
ssl.privkey = "/userdata/httpd/server.key"
ssl.openssl.ssl-conf-cmd = ( "MinProtocol" => "TLSv1.2" )
```

and delete the whole `$SERVER["socket"] == ":8443" { ... }` block. Do not just comment out `server.port = 8080`. Without it lighttpd falls back to port 80 and serves plain HTTP there.

**HTTP only** (no TLS): delete or comment out the whole `$SERVER["socket"] == ":8443" { ... }` block. Basic auth then sends the password readable on the network. `start-httpd.sh` still creates the certificate on first start; it is just not used.

`start-httpd.sh` checks the new file with `lighttpd -tt`. If the check fails, it keeps the old config and the running server, and writes the error to `/mnt/sdcard/logs/httpd.log`.

## Users and passwords

`gen-htpasswd.sh` creates and edits the password file on the host:

```sh
./gen-htpasswd.sh [--file FILE] [--random | --delete] USER
```

| option | default | meaning |
|---|---|---|
| `--file FILE` | `secrets/htpasswd` | file to edit |
| `--random` | off | generate a 24-character password and print it once |
| `--delete` | off | remove `USER` from the file |

- The password is asked twice on a terminal, or read as one line from stdin.
- The hash is SHA-512 crypt (`openssl passwd -6`).
- `USER` may contain only `A-Z a-z 0-9 . _ -`.
- `secrets/` is in `.gitignore`; it is created with mode 700, the file with mode 600.

```sh
cd buddy-addons
./gen-htpasswd.sh camera                # add or change user camera, password asked twice
./gen-htpasswd.sh --random camera       # new random password, printed once
./gen-htpasswd.sh --delete camera       # remove user camera
```

Apply the file (also after changing or removing a user):

```sh
scp -O secrets/htpasswd root@CAMERA_IP:/mnt/sdcard/bin/htpasswd
ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-httpd.sh
```

`start-httpd.sh` installs the changed file and restarts lighttpd, so the old password stops working at once.

Accepted hash formats, if you make the file another way: crypt `$6$`, `$5$`, `$2b$`, `$1$` (musl crypt), `$apr1$` and `{SHA}`. Checking a SHA-512 crypt (`$6$`) hash takes about 0.14-0.18 s on the camera's Cortex-A7; the login cache hides this after the first request.

The password for the user `camera` on this camera is in `buddy-addons/secrets/camera.password`. That file is local only (gitignored) and was created by the deployment.

## Use from a host

Mirror the card over HTTP or HTTPS (`--ask-password` prompts; `--password=PASS` also works):

```sh
wget --mirror --no-parent --no-host-directories -e robots=off --user=USER --ask-password http://CAMERA_IP:8080/
wget --mirror --no-parent --no-host-directories -e robots=off --no-check-certificate --user=USER --ask-password https://CAMERA_IP:8443/
```

wget sends the credentials only after the first 401. `--auth-no-challenge` is optional; it sends them with the first request and skips that extra round trip.

Large lp_app logs live in `/logs`; skip them with `-X /logs` (wget):

```sh
wget --mirror --no-parent --no-host-directories -e robots=off -X /logs --no-check-certificate --user=USER --ask-password https://CAMERA_IP:8443/
```

Single directory with curl, without certificate checks (curl prompts for the password):

```sh
curl -k -u USER https://CAMERA_IP:8443/timelapse/
```

Browsers show a login prompt for realm `camera`.

To pin the certificate instead of `-k`, copy it to the host. The CN and SAN are the camera's hostname, so map that name to the IP with `--resolve`:

```sh
scp -O root@CAMERA_IP:/userdata/httpd/server.crt camera.crt
curl -u USER --cacert camera.crt --resolve HOSTNAME:8443:CAMERA_IP https://HOSTNAME:8443/
```

## Use a certificate made on the host

Instead of the certificate the camera makes on first start, you can create one on the host with `openssl` (1.1.1 or newer) and install it over ssh. That lets you choose the names, add the camera's IP address as a SAN so clients can pin it without `--resolve`, and keep a copy of the key on the host.

```sh
cd buddy-addons
./gen-cert.sh --cn Rockchip --ip CAMERA_IP     # -> certs/Rockchip/server.key, server.crt
./install-cert.sh root@CAMERA_IP               # upload, restart lighttpd, check served fingerprint
curl -u USER --cacert certs/Rockchip/server.crt https://CAMERA_IP:8443/
```

`gen-cert.sh` options:

| option | default | meaning |
|---|---|---|
| `--cn NAME` | `camera` | common name; also added as a `DNS:` SAN |
| `--dns NAME` | none | extra `DNS:` SAN, repeatable |
| `--ip ADDR` | none | `IP:` SAN, repeatable |
| `--days N` | 10 years from today | validity |
| `--out DIR` | `certs/<cn>` | output directory (mode 700) |
| `--force` | off | replace an existing pair in `DIR` |

The key is ECDSA P-256 (PKCS#8 PEM, mode 600), the certificate is self-signed with SHA-256, `CA:FALSE`, key usage `digitalSignature` and extended key usage `serverAuth`. `certs/` is in `.gitignore` because it holds private keys.

`install-cert.sh [--dir DIR] [--port N] SSH_TARGET`:
- Uses `certs/<the only directory>` unless `--dir` is given. Before touching the camera, it refuses a key that does not belong to the certificate, or an expired certificate.
- Copies the pair to `/userdata/httpd/server.{key,crt}`, keeps the previous pair as `server.{key,crt}.bak`, and runs `start-httpd.sh restart`.
- If `start-httpd.sh` rejects the pair (its `lighttpd -tt` check loads the certificate), the script puts the previous pair back and exits 1. The running server keeps serving the old certificate.
- At the end it compares the SHA-256 fingerprint served on port 8443 with the local one. `SSH_TARGET` can be an `~/.ssh/config` alias; the real host name comes from `ssh -G`.
- The remote part runs with `set -e`, so it stops at the first failing command.

`gen-cert.sh` also works with bash older than 4.4 when no `--dns`/`--ip` are given.

`start-httpd.sh` only creates a certificate when none exists, so an installed pair stays across reboots. If a firmware update wipes `/userdata`, the camera makes its own certificate again; rerun `install-cert.sh`. To go back to a camera-made certificate, delete `/userdata/httpd/server.key` and `server.crt` and run `start-httpd.sh restart`.

## Persistence

| location | survives reboot | survives firmware update | notes |
|---|---|---|---|
| `/userdata/httpd/*` | yes | may be wiped | TLS key and cert regenerated by the camera if wiped (clients pinning the cert must re-fetch it; a host-made pair must be installed again with `install-cert.sh`); `lighttpd.conf` and `htpasswd` re-copied from the card |

Shared paths, including `/tmp/lighttpd.pid` and `/tmp/lighttpd.log`, are in [Persistence and memory](README.md#persistence-and-memory).

## Verified

On the host (qemu-user):
- `lighttpd -tt` on `device/lighttpd.conf` is clean.
- HTTPS only (`server.port = 8443` with the ssl.* lines global, socket block deleted): `-tt` clean, HTTPS 200 with TLS 1.2 and 1.3 and basic auth, nothing on 8080. HTTP only (socket block deleted): `-tt` clean, HTTP 200, nothing on 8443. With `server.port` removed and the socket block kept, lighttpd tried to bind `0.0.0.0:80`.
- lighttpd's own listing output (auto-layout off) has no `<style>`, no `<script>` and no `?C=` sort links.
- Denied paths return 403 over HTTP and HTTPS: `rclone.conf`, `RCLONE.CONF`, `bin/authorized_keys`, `/.Trash-1000/`, a nested `/.hidden/`.
- UTF-8 file names are served.
- TLS 1.2 (`ECDHE-ECDSA-AES256-GCM-SHA384`) and TLS 1.3 (with HTTP/2) work; TLS 1.1 is refused.
- PUT returns 404, DELETE returns 501.
- `wget --mirror` over HTTP and HTTPS reproduced the tree with identical file contents.
- `mbedtls-gen-key` and `mbedtls-cert-write` produce a valid P-256 self-signed certificate.
- Basic auth: without `htpasswd` every request got 401. With it: anonymous 401, wrong password 401, right password 200, over HTTP and HTTPS. `$6$`, `$5$` and `$apr1$` hashes were accepted. The header is `WWW-Authenticate: Basic realm="camera", charset="UTF-8"`.
- `/bin/htpasswd` returned 403 with and without a login and was not listed.
- Authenticated `wget --mirror` exited 0.

On the camera:
- Files uploaded to `/mnt/sdcard/bin` with md5 matching the build.
- Hook block placed after the remount line in the card's `lp_app.sh` (original saved as `/mnt/sdcard/lp_app.sh.bak-pre-httpd`).
- The first manual `start-httpd.sh` run installed the binaries and config, generated the P-256 key and a self-signed cert (CN=Rockchip, the camera's hostname) and started lighttpd in about 1 s. busybox has no `sha256sum`/`base64`, so the certificate fingerprint is computed on the host.
- After deleting `server.key`/`server.crt` and running `start-httpd.sh restart`, the new cert was CN=Rockchip, notBefore Oct 31 22:11:33 2026 GMT, notAfter Oct 31 22:11:33 2036 GMT (camera clock 23:11:32 UTC, matching the host). HTTPS returned 200 with `-k` and with the cert pinned via `--cacert`/`--resolve`.
- lighttpd RSS 452-668 KB, cwd `/`, no open files on the card.
- HTTP and HTTPS return 200; TLS 1.2 (`ECDHE-ECDSA-AES256-GCM-SHA384`) and TLS 1.3 (HTTP/2) work.
- Certificate pinning with `--cacert` + `--resolve Rockchip:8443:IP` returned 200.
- Denied paths return 403: `bin/authorized_keys`, `BIN/AUTHORIZED_KEYS`, `/.Trash-1000/`, `/userdata/`, `/USERDATA/current/xhr_http_token.conf`.
- Uploading a broken config was rejected with the parser error in `httpd.log` while the running server kept serving; uploading a changed config restarted the server.
- `wget --mirror` of the card (excluding the 611 MB of lp_app logs with `-X /logs`) exited 0 with files identical to the originals.
- A 22 MB log file downloaded at 4.7 MB/s over HTTP and 2.2 MB/s over HTTPS.
- After `sync; reboot -f` the hook started lighttpd on its own (HTTP up about 30 s after the reboot), the card came back mounted with `fmask=0000,dmask=0000`, and `sync_loop.sh` and lp_app started as usual.
- Styled listing: uploading `lighttpd.conf` and `dirlisting-header.html` and rerunning `start-httpd.sh` installed both and restarted lighttpd. The listing rendered in Chromium over HTTPS with the inline style. The HTML contained no `<script>` and no `<link>`. `wget --mirror -X /logs` still exited 0, and the only new file it fetched was `bin/dirlisting-header.html` itself.
- Listing title: neither the repo's device files nor the card's template contain a host name; the template has only the placeholders. With `drill` installed, a manual `start-httpd.sh` logged `listing title: buddy-cam-1.intra.hlds.pl (reverse DNS)`. After `sync; reboot -f` the boot run logged `listing title: Rockchip for now; retrying reverse DNS in the background`. About a minute after boot the background job logged `listing title: buddy-cam-1.intra.hlds.pl (reverse DNS)` and exited, removing `/tmp/httpd-title.pid`. The served page then had `<title>buddy-cam-1</title>` and the heading `buddy-cam-1` / `buddy-cam-1.intra.hlds.pl`, and rendered that way in Chromium.
- Title follow-up: with `/userdata/bin/drill` deleted and a stand-in retry job registered in `/tmp/httpd-title.pid`, `start-httpd.sh` reinstalled `drill` from the card and set the title from reverse DNS. It stopped the old job and removed the pid file, all in about 1 s. `timeout -t 2` around a lookup sent to the dead DNS server 192.168.1.10 returned after 2 s.
- Host-made certificate: `gen-cert.sh --cn Rockchip --ip 192.168.1.75` gave a P-256 cert valid Nov 1 2026 to Nov 1 2036. `install-cert.sh root@192.168.1.75` installed it, and the served fingerprint matched the local one. `curl --cacert` by IP, without `--resolve`, returned 200.
- Rejected pair: mbedTLS 3.6 cannot load an Ed25519 certificate. Installing one made `start-httpd.sh` fail its `lighttpd -tt` check (`Signature algorithm (oid) is unsupported`). `install-cert.sh` restored the previous pair, exited 1, and the server kept serving the previous certificate.
- A key that did not match the certificate was refused on the host before anything was uploaded.
- Afterwards the camera's own certificate (CN=Rockchip, fingerprint `C6:44:5B:7F:…:56:67`) was put back with `install-cert.sh --dir`, and the served fingerprint matched it.
- Basic auth: `htpasswd` uploaded to the card was installed by `start-httpd.sh` (mode 600, server restarted). Anonymous and wrong password got 401, the right password 200, over HTTP and HTTPS.
- The first authenticated request took about 0.14-0.18 s (SHA-512 crypt on the Cortex-A7); cached ones 0.016-0.07 s.
- `/bin/htpasswd` returned 403 with a valid login and was absent from the `/bin/` listing.
- Authenticated `wget --mirror -X /logs` over HTTPS exited 0 (23 files, 1.8 s).
- After changing the password with `gen-htpasswd.sh` and rerunning `start-httpd.sh`, the old password got 401 and the new one 200.
- After `sync; reboot -f` lighttpd came up on its own and an authenticated HTTPS request returned 200.
