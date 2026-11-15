# SSH access (dropbear)

Instead of telnet, the camera runs a Dropbear ssh server on port 22 with public-key login for `root`.
Password logins are compiled out. The same binary also provides `scp`, `dbclient` and `dropbearkey`.

## How it works

- `buddy-addons/build-dropbear.sh` builds Dropbear 2026.94 as one static ARMv7 binary, `out/dropbearmulti`
  (applets `dropbear`, `dropbearkey`, `dbclient`, `scp`). Build-time choices:
  - password auth disabled (`DROPBEAR_SVR_PASSWORD_AUTH 0`), keys only;
  - default PATH for non-login commands: `/userdata/bin:/oem/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
  - `DROPBEAR_REEXEC` disabled.
- Files on the microSD card:
  - `/mnt/sdcard/bin/dropbearmulti` (from `out/dropbearmulti`);
  - `/mnt/sdcard/bin/start-sshd.sh` (from `buddy-addons/device/start-sshd.sh`);
  - `/mnt/sdcard/bin/authorized_keys` (your public keys, one per line);
  - `/mnt/sdcard/lp_app.sh` with the block from `buddy-addons/device/sshd-hook.sh` pasted in.
- On every boot the hook block runs `start-sshd.sh` (if present on the card), which:
  - copies `dropbearmulti` (and `rsync`, `drill` if present) to `/userdata/bin/` when the md5 differs,
    and creates the applet symlinks;
  - copies `authorized_keys` from the card to `/userdata/ssh/authorized_keys` (mode 600) when it differs;
    the card is authoritative;
  - generates `/userdata/ssh/dropbear_ed25519_host_key` on first run;
  - bind-mounts a copy of `/etc/passwd` (`/userdata/ssh/passwd`) with root's home set to `/userdata/ssh`,
    because dropbear's permission check on the path to `authorized_keys` otherwise fails on this camera;
  - starts `dropbear -F -m -p 22 -K 5 -r <hostkey> -D /userdata/ssh -P /tmp/dropbear.pid`, or restarts the
    listener (open sessions stay) if the binary on the card changed or the running one has other options.
- Keepalive: `-K 5` makes dropbear send a keepalive after 5 s without traffic and drop the connection after 3
  unanswered ones (`DEFAULT_KEEPALIVE_LIMIT`), so sessions of vanished clients end after about 15 s.
- Reboot: `task buddy:reboot` (`safe-reboot.sh`) stops every dropbear and `telnetd` process 1 s before
  `reboot -f`, after its own session has ended. The kernel then closes their TCP connections, and other open
  sessions end at once with `Connection to ... closed by remote host.` instead of hanging. A power cut or a
  plain `reboot -f` gives no such close; only a client keepalive notices that (below).
- Logs: start steps in `/mnt/sdcard/logs/dropbear.log` (fallback `/tmp/dropbear.log`); the daemon itself logs
  to `/tmp/dropbear.log` (lost on reboot). The daemon keeps nothing open on the card, so the hook's
  `umount`/remount still works.
- Persistence: `/userdata/ssh/*` survives reboots but may be wiped by a firmware update; then the host key is
  regenerated and `authorized_keys` is copied again from the card.
- Telnet: `telnetd` is started only by the card's `lp_app.sh`. The repo hook templates (`sdcard/`,
  `sdcard_rsync/`, `sdcard_no_rsync/`) still start it; ssh replaces telnet only once you comment that line out.
  With telnet disabled there is no telnet fallback if ssh fails to start.

## What to change

!!! warning "Mandatory: your public key"
    Put your own public key(s) in `/mnt/sdcard/bin/authorized_keys` (one per line), e.g.
    `cp ~/.ssh/id_ed25519.pub bin/authorized_keys` in the root of the mounted card. There is no default key and
    no password login, so without it you cannot log in. Never copy private keys to the card.

- `/mnt/sdcard/bin/authorized_keys` — the key list. Edit it on the card to add/revoke keys; it replaces
  `/userdata/ssh/authorized_keys` on the next boot (or the next run of `start-sshd.sh`).
- `/mnt/sdcard/lp_app.sh` — paste the block from `buddy-addons/device/sshd-hook.sh` right **before**
  `umount /mnt/sdcard` (`sdcard/`, `sdcard_rsync/`, `sdcard_no_rsync/` variants) or before the final
  `lp_app --noshell ...` line (`8/` variant).
- Telnet on/off — the `telnetd` line in `/mnt/sdcard/lp_app.sh`. Repo templates: enabled. Re-enable it only
  temporarily for a first install or recovery.

!!! warning "Disable telnet after ssh works"
    If you start from a repo hook template (or a card hook that still runs `telnetd`), comment out the
    `telnetd` line in `/mnt/sdcard/lp_app.sh` once ssh key login works. Otherwise telnet (port 23,
    no authentication) stays open alongside ssh.

- `buddy-addons/device/start-sshd.sh`, variable `PORT` — default `22`. Change only if you need another port.
  `KEEPALIVE` — default `5` (seconds); `0` turns the server keepalive off. A changed value restarts the
  listener on the next run of the script. Other variables there (`SRC=/mnt/sdcard/bin`, `BIN=/userdata/bin`,
  `SSHDIR=/userdata/ssh`, `HOSTKEY`, `PIDFILE=/tmp/dropbear.pid`) normally need no change.
- `Taskfile.yml`, var `CAMERA_HOST` — default `192.168.1.75`; set it to your camera's IP so that
  `task buddy:sync` can reach it over ssh.
- `Taskfile.yml`, var `SSH_OPTS` — ssh client options used by every task. Default:
  `-o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3`, so a task's session ends about
  15 s after the camera stops answering (power cut, `reboot -f`, Wi-Fi loss) instead of hanging.
- Host side (optional): the same client keepalive for your own ssh sessions, in `~/.ssh/config`:

    ```text
    Host camera
        HostName CAMERA_IP
        User root
        IdentityFile ~/.ssh/id_ed25519
        ServerAliveInterval 5
        ServerAliveCountMax 3
    ```

!!! note
    If `/userdata/ssh` is wiped (e.g. by a firmware update), the host key changes; remove the camera's old entry
    from your `known_hosts`.

## Build and deploy

```sh
cd buddy-addons
./build-dropbear.sh                                   # -> out/dropbearmulti
ADDONS=$PWD
cd /path/to/mounted/sdcard                            # card root
cp "$ADDONS/out/dropbearmulti" "$ADDONS/device/start-sshd.sh" bin/
cp ~/.ssh/id_ed25519.pub bin/authorized_keys
sync
```

Paste `device/sshd-hook.sh` into `lp_app.sh` in the card root as described above, put the card back and
power-cycle.

Without card access (first install), re-enable telnet and upload the files as described in
`buddy-addons/README.md` ("Upload via telnet") and `buddy-addons/dropbear.md` ("Install via telnet").

Later updates can go over ssh with `task buddy:sync`. It rsyncs the staged `device/` scripts and `authorized_keys`
(built from `SSH_PUBKEYS` in `Taskfile.yml`, replacing the key list on the card) to `/mnt/sdcard/bin/`; it does
**not** include `dropbearmulti`, and excludes `*-hook.sh`.

## Verify

```sh
ssh root@CAMERA_IP 'dropbear -V'
ssh root@CAMERA_IP 'tail -5 /mnt/sdcard/logs/dropbear.log; tail -3 /tmp/dropbear.log'
ssh root@CAMERA_IP 'grep /mnt/sdcard /proc/mounts'
scp -O somefile root@CAMERA_IP:/userdata/   # -O: legacy scp, there is no sftp-server
```

Expect `started dropbear on port 22` in `dropbear.log` and `Pubkey auth succeeded for 'root'` in
`/tmp/dropbear.log`. Host key fingerprint on the camera:
`dropbearkey -y -f /userdata/ssh/dropbear_ed25519_host_key`.

Recovery if ssh does not come up: take the card out, uncomment `telnetd` in `lp_app.sh` (or restore
`lp_app.sh.bak-pre-notelnet` / `lp_app.sh.bak-pre-sshd`) and power-cycle. Do not use `lp_stop`: it skips the
whole hook, so neither ssh nor telnet starts.

## Source files

- `buddy-addons/dropbear.md`
- `buddy-addons/build-dropbear.sh`
- `buddy-addons/device/sshd-hook.sh`
- `buddy-addons/device/start-sshd.sh`
- `buddy-addons/README.md`
- `Taskfile.yml`
