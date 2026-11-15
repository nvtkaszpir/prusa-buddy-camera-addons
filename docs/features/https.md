# HTTP/HTTPS file server (lighttpd)

A read-only lighttpd web server on the camera serves the microSD card (`/mnt/sdcard`). The shipped config serves
**plain HTTP on port 8080 without a password**, the fastest setup on this camera; HTTPS (8443) and HTTP basic auth
are in the config as commented-out blocks. You can fetch files such as timelapses with a browser, `wget` or
`curl` instead of using [rsync](rsync.md). lighttpd was picked after comparing several servers in
`buddy-addons/httpd-comparison.md`. It is one small static binary with TLS (mbedTLS) built in, and it can make its
own key on the camera. For a speed comparison of HTTP, HTTPS and rsync over ssh, see
[rsync: Transfer speed](rsync.md#transfer-speed).

!!! danger "No password: anyone on the network can read the card"
    Without TLS and basic auth, every file lighttpd serves is readable by anyone who can reach port 8080. The
    `lp_app` logs in `logs/` can contain the Prusa Connect token and Wi-Fi credentials
    (see [lp_app](../findings/cam-3.1.3/oem/usr/sbin/lp_app.md)), so the shipped config denies `logs/` and the
    card's `userdata/`; fetch logs over ssh/rsync. Keep the camera on an isolated network, serve only
    `timelapse/` (`server.document-root`), or turn HTTPS and auth back on (see "What to change").

## How it works

- Binaries built by `buddy-addons/build-lighttpd.sh` (lighttpd 1.4.85 + mbedTLS 3.6.7 + PCRE2):
  - `out/lighttpd`: the server, with its modules linked in statically.
  - `out/mbedtls-gen-key`, `out/mbedtls-cert-write`: make the TLS key and self-signed certificate on the
    camera at first start.
- Files on the microSD card (`/mnt/sdcard/bin/`): `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write`,
  `start-httpd.sh`, `lighttpd.conf`, `dirlisting-header.html` (optional, listing style), `htpasswd`, and
  optionally `drill` (reverse DNS for the listing title).
- Boot: paste `buddy-addons/device/httpd-hook.sh` into `/mnt/sdcard/lp_app.sh` right **after** the
  `mount -t vfat -o rw,...` line that remounts the card, and before `/tmp/sync_loop.sh`. This is not the
  same place as the ssh hook. The hook runs `sh /mnt/sdcard/bin/start-httpd.sh`, which:
  1. copies the binaries to `/userdata/bin/` when their md5 differs from the copies on the card;
  2. creates `/userdata/httpd/` (mode 700);
  3. on first start, makes `/userdata/httpd/server.key` (ECDSA P-256) and a self-signed
     `/userdata/httpd/server.crt` with CN and `DNS:` SAN set to `hostname`, valid for 10 years;
  4. installs `/mnt/sdcard/bin/lighttpd.conf` as `/userdata/httpd/lighttpd.conf` only if `lighttpd -tt`
     accepts it. If the check fails, it keeps the installed config and the running server;
  5. copies `/mnt/sdcard/bin/htpasswd` to `/userdata/httpd/htpasswd` (mode 600) and restarts lighttpd when
     that file changed;
  6. fills `@HOSTNAME@`/`@FQDN@` in the listing header, then starts lighttpd. A running server is
     restarted only when the binary, config or `htpasswd` changed, or when you pass `restart`.
- Ports: the shipped `buddy-addons/device/lighttpd.conf` sets `server.port = 8080`, plain HTTP only (since
  2026-11-14; before that it served HTTPS only on 8443). The commented-out `$SERVER["socket"] == ":8443"` block
  adds HTTPS with TLS 1.2 and 1.3. `start-httpd.sh` still creates the key and certificate on the first start.
- Served content: document root `/mnt/sdcard`, read-only (GET/HEAD), with a directory listing and no
  JavaScript or sort links, so `wget --mirror` downloads no duplicate pages. These are denied (403) and hidden
  from listings:
  - dotfiles at any depth;
  - `rclone.conf`, `*.key`, `*.pem`, `authorized_keys`, `htpasswd`;
  - the card's `/userdata/`, which holds the Prusa Connect token and Wi-Fi password copies;
  - `/logs/` (the `lp_app` and add-on logs, which can contain the token and Wi-Fi credentials). The block in
    `lighttpd.conf` says how to serve them again; do that only with HTTPS and auth on.

  URL matching ignores case.
- Auth: off in the shipped config (the `auth.*` lines are commented out). With them enabled, basic auth applies
  to every URL (realm `camera`, `require valid-user`), the user file is `/userdata/httpd/htpasswd`, a successful
  login is cached for 600 s, and every request gets 401 while the user file is missing.
- Logs: `/mnt/sdcard/logs/httpd.log` (start script; `/tmp/httpd.log` if the logs dir is missing),
  `/tmp/lighttpd.log` (server error log, no access log), pid in `/tmp/lighttpd.pid`.
- Persistence: `/userdata/httpd/*` survives reboots but a firmware update may wipe it. If that happens, the
  camera makes a new key and certificate, and the config and `htpasswd` are copied again from the card.

## What to change

!!! note "htpasswd: only with basic auth"
    The shipped config does not ask for a password, so `htpasswd` is only needed once you enable the `auth.*`
    lines. Create it on the host with `buddy-addons/gen-htpasswd.sh`. It writes `buddy-addons/secrets/htpasswd`
    (gitignored, mode 600) with SHA-512 crypt hashes. Never commit it or put it anywhere the server publishes.

- **Users/passwords**: `buddy-addons/gen-htpasswd.sh [--file FILE] [--random | --delete] USER`
  - `--file`: default `secrets/htpasswd`.
  - `USER`: may contain only `A-Z a-z 0-9 . _ -`.
  - `--random`: prints a 24-character password once.
  - `--delete`: removes `USER`.

  After any change, copy the file to `/mnt/sdcard/bin/htpasswd` and rerun `start-httpd.sh`.
- **TLS certificate** (optional): by default the camera makes a self-signed certificate on first start, with
  CN and SAN set to `hostname`. To pick the names yourself, add the camera's IP as a SAN, or keep the key on
  the host, use:
  - `buddy-addons/gen-cert.sh`:
    - `--cn NAME`: default `camera`, also added as a `DNS:` SAN.
    - `--dns NAME`: repeatable.
    - `--ip ADDR`: repeatable; set the camera IP here.
    - `--days N`: default 10 years.
    - `--out DIR`: default `certs/<cn>`.
    - `--force`: replace an existing pair.
  - `buddy-addons/install-cert.sh [--dir DIR] [--port N] SSH_TARGET`: uploads the pair over ssh (needs
    [ssh](ssh.md)), restarts lighttpd and checks the fingerprint the camera serves. `--port` defaults to
    8443.

  `certs/` holds private keys and is gitignored. To go back to a camera-made certificate, delete
  `/userdata/httpd/server.key` and `server.crt`, then run `start-httpd.sh restart`.
- **Served path**: `buddy-addons/device/lighttpd.conf`, `server.document-root`, default `"/mnt/sdcard"`.
  Change it to serve only a subdirectory, such as `/mnt/sdcard/timelapse`.
- **Ports**: `lighttpd.conf`, `server.port` and the commented-out `$SERVER["socket"] == ":8443"` block. Ports 22,
  23 and 554 are already used on the camera. The "ports" comments in the config explain HTTP + HTTPS and HTTPS
  only (for HTTPS also add `"mod_mbedtls"` to `server.modules`).

!!! warning "Plain HTTP exposes the password"
    Basic auth over plain HTTP sends the password readable on the network. When you turn auth on, turn TLS on
    too. Do not just comment out `server.port`, because lighttpd then falls back to plain HTTP on port 80.

- **Auth on**: uncomment the `auth.*` lines in `lighttpd.conf`, add `"mod_auth", "mod_authn_file"` to
  `server.modules`, and create `htpasswd` (above).
- **Listing look/title** (optional): `buddy-addons/device/dirlisting-header.html` uses the placeholders
  `@HOSTNAME@`/`@FQDN@`. Do not add external files (CSS, fonts, images, scripts), or `wget --mirror` would
  download them too.
- **Camera address**: examples use `CAMERA_IP`. In `Taskfile.yml`, `CAMERA_HOST` defaults to `192.168.1.75`;
  set it to your camera.

## Build and deploy

```sh
cd buddy-addons
./build-lighttpd.sh                      # -> out/lighttpd, out/mbedtls-gen-key, out/mbedtls-cert-write
./gen-htpasswd.sh camera                 # -> secrets/htpasswd (or --random)

ADDONS=$PWD
cd /path/to/mounted/sdcard               # card root
mkdir -p bin
cp "$ADDONS/out/lighttpd" "$ADDONS/out/mbedtls-gen-key" "$ADDONS/out/mbedtls-cert-write" \
   "$ADDONS/device/start-httpd.sh" "$ADDONS/device/lighttpd.conf" "$ADDONS/device/dirlisting-header.html" bin/
cp "$ADDONS/secrets/htpasswd" bin/htpasswd
sync
# then paste $ADDONS/device/httpd-hook.sh into lp_app.sh after the rw remount line
```

Later config or script changes can go over ssh with `task buddy:sync`. It stages `buddy-addons/device/` and
rsyncs it to `root@CAMERA_HOST:/mnt/sdcard/bin/`, but it does not include the lighttpd binaries or
`htpasswd`, which you copy yourself. Then apply them:

```sh
scp -O secrets/htpasswd root@CAMERA_IP:/mnt/sdcard/bin/htpasswd
ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-httpd.sh
```

Optional host-made certificate:

```sh
./gen-cert.sh --cn buddy-cam --ip CAMERA_IP   # -> certs/buddy-cam/server.{key,crt}
./install-cert.sh root@CAMERA_IP
```

## Verify

On the camera:

```sh
cat /mnt/sdcard/logs/httpd.log          # "started lighttpd", "installed htpasswd", REJECTED lines
cat /tmp/lighttpd.log
/userdata/bin/lighttpd -tt -f /userdata/httpd/lighttpd.conf
sh /mnt/sdcard/bin/start-httpd.sh restart   # or: stop
```

From a host:

```sh
curl http://CAMERA_IP:8080/
curl http://CAMERA_IP:8080/timelapse/file.avi -o file.avi
wget -c http://CAMERA_IP:8080/timelapse/file.avi                   # -c continues a broken download
wget --mirror --no-parent --no-host-directories -e robots=off http://CAMERA_IP:8080/   # logs/ is not served
```

With HTTPS and auth enabled instead (`-u USER` makes curl ask for the password; `-k` skips the check of the
self-signed certificate):

```sh
curl -k -u USER https://CAMERA_IP:8443/
wget --mirror --no-parent --no-host-directories -e robots=off -X /logs \
  --no-check-certificate --user=USER --ask-password https://CAMERA_IP:8443/
curl -u USER --cacert certs/buddy-cam/server.crt https://CAMERA_IP:8443/     # pinned: gen-cert.sh with --ip
```

Denied paths such as `/rclone.conf`, `/bin/htpasswd`, `/userdata/` or `/logs/` should get `403`. Checked on the
maintainer's camera on 2026-11-14 with this config: `/` and `/timelapse/` gave 200, port 8443 refused the
connection, and `/userdata/`, `/USERDATA/xhr_config.ini`, `/logs/`, `/LOGS/httpd.log`,
`/logs/2026-11-13_00.log`, `/bin/htpasswd`, `/bin/authorized_keys` and `/.Trash-1000/` gave 403; the root
listing showed no `logs/` or `userdata/` entry.

## Source files

- `buddy-addons/lighttpd.md`
- `buddy-addons/httpd-comparison.md`
- `buddy-addons/build-lighttpd.sh`
- `buddy-addons/gen-cert.sh`
- `buddy-addons/install-cert.sh`
- `buddy-addons/gen-htpasswd.sh`
- `buddy-addons/device/lighttpd.conf`
- `buddy-addons/device/httpd-hook.sh`
- `buddy-addons/device/start-httpd.sh`
- `buddy-addons/device/dirlisting-header.html`
- `Taskfile.yml`
