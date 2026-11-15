# dropbear (ssh server)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile), [Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet).

Status: running on the camera (Prusa Core One L, 192.168.1.75). sshd starts from the microSD boot hook and survives reboots. Key login and rsync over ssh were verified on the device. See [Verified](#verified).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/dropbearmulti` | Dropbear 2026.94, `build-dropbear.sh` | `dropbear` (sshd), `dropbearkey`, `dbclient`, `scp`, one binary | 379028 B | `560da13a411023da7e7f643c4fe95c6ad076ae73316146ad7deabe4c8dcc0d58` |

```sh
./build-dropbear.sh                               # -> out/dropbearmulti
qemu-arm-static out/dropbearmulti dropbear -V     # Dropbear v2026.94
```

Build-time choices:
- Dropbear's PATH is set to `/userdata/bin:/oem/bin:/usr/bin:/bin:/usr/sbin:/sbin`. This applies to non-login commands only; `/etc/profile` overrides it for login shells (see [Target facts](README.md#target-facts)).
- Password logins are compiled out. Only public keys are accepted.
- `DROPBEAR_REEXEC` is disabled. Dropbear's per-connection re-exec only adds ASLR, and a non-PIE static binary gets nothing from it. It also needs `execveat(AT_EMPTY_PATH)`, which qemu-user does not implement, so this also lets the test suite run.

## Install on the card

Layout on the card (`rsync` and `drill` are installed by the same script, see [rsync.md](rsync.md) and [drill.md](drill.md)):

```
/mnt/sdcard/bin/dropbearmulti      <- out/dropbearmulti
/mnt/sdcard/bin/start-sshd.sh      <- device/start-sshd.sh
/mnt/sdcard/bin/authorized_keys    <- your public key(s), one per line
/mnt/sdcard/lp_app.sh              <- your existing hook, with device/sshd-hook.sh pasted in
```

```sh
cp out/dropbearmulti device/start-sshd.sh "$SD/bin/"
cp ~/.ssh/id_ed25519.pub "$SD/bin/authorized_keys"
sync
```

Add the ssh block (`device/sshd-hook.sh`) to your hook right before `umount /mnt/sdcard`, as described in [Install via microSD](README.md#install-via-microsd).

### What happens at boot

The ssh block runs `start-sshd.sh`, which:
- copies `dropbearmulti`, `rsync` and `drill` (if present on the card) to `/userdata/bin/` when their md5 differs from the card's;
- creates the applet links `dropbear`, `dropbearkey`, `dbclient`, `scp`;
- copies `authorized_keys` from the card to `/userdata/ssh/` when it differs (the card wins);
- generates `/userdata/ssh/dropbear_ed25519_host_key` on first run;
- bind-mounts a copy of `/etc/passwd` over the real one, with root's home set to `/userdata/ssh` (explained below);
- starts `dropbear -F -m -p 22 -r <hostkey> -D /userdata/ssh -P /tmp/dropbear.pid` in the background. If a server is already running it does nothing, unless the dropbear binary changed on the card, in which case it restarts the server.

Logs: `start-sshd.sh` writes its own steps to `/mnt/sdcard/logs/dropbear.log` (or `/tmp/dropbear.log` if the logs dir is missing). The running dropbear daemon logs (connections, auth) to `/tmp/dropbear.log`, which is lost on reboot. The daemon is kept off the card on purpose: it runs with cwd `/` and opens nothing on `/mnt/sdcard`, because the hook unmounts and remounts the card right after it starts, and an open file would make that `umount` fail with "busy".

Why the passwd copy: dropbear refuses pubkey auth unless every directory on the path from `authorized_keys` up to the user's home directory is owned by root or the user and not group- or world-writable. Its check walks all the way up to `/` unless it reaches the home directory first. On this camera `/` is `775` owned by uid 1001, and root's home (`/root`) does not exist, so keys under `/userdata` would silently fail. Making root's home `/userdata/ssh` stops the walk there. This was confirmed in the dropbear source (`src/svr-authpubkey.c`, `checkpubkeyperms`), and the bind mount works on the camera.

Side effect: a telnet root login (if telnet is re-enabled) also gets `/userdata/ssh` as its home directory. Nothing else changes.

## Install via telnet

Telnet is off by default on the camera; this method needs it re-enabled first (see [Upload via telnet](README.md#upload-via-telnet)). Upload `dropbearmulti` (and `rsync`, `drill` if wanted) as described there. Also create the key directory:

```sh
mkdir -p /userdata/ssh
chmod 700 /userdata/ssh
```

Then the scripts and key:

```sh
# paste device/start-sshd.sh into /userdata/bin/start-sshd.sh the same way (base64 paste)
# paste your public key into /userdata/ssh/authorized_keys, then:
chmod 600 /userdata/ssh/authorized_keys
sh /userdata/bin/start-sshd.sh
```

Without the card, `start-sshd.sh` uses `/userdata/bin` copies. The card-copy step is skipped because `/mnt/sdcard/bin` is missing. The script still needs `dropbearmulti` in `/userdata/bin`, or it exits with `no /userdata/bin/dropbearmulti`. The `/mnt/sdcard/bin/authorized_keys` step is skipped too, so the key you pasted stays.

Logs go to `/mnt/sdcard/logs/dropbear.log` when that directory exists, otherwise to `/tmp/dropbear.log`, which is lost on reboot.

## Use ssh and scp

```sh
ssh root@CAMERA_IP
```

Key auth only. Recommended `~/.ssh/config` entry:

```
Host camera
    HostName CAMERA_IP
    User root
    IdentityFile ~/.ssh/id_ed25519
```

The first connection asks you to accept the host key (`ssh-ed25519`). The fingerprint is written to `/mnt/sdcard/logs/dropbear.log` when the key is generated. To print it later, run `dropbearkey -y -f /userdata/ssh/dropbear_ed25519_host_key` on the camera.

Where to look when something fails:
- `/mnt/sdcard/logs/dropbear.log`: the startup steps from `start-sshd.sh` (install, key, bind mount, start).
- `/tmp/dropbear.log`: the running daemon (connections, `Pubkey auth succeeded` or refused, permission warnings). This file is lost on reboot.

scp: `scp -O file root@CAMERA_IP:/userdata/`. The `-O` flag forces the legacy scp protocol. OpenSSH's default SFTP mode needs `sftp-server`, which is not on the camera.

## Persistence and memory

| location | survives reboot | survives firmware update | notes |
|---|---|---|---|
| `/userdata/ssh/*` | yes | may be wiped | host key regenerated if wiped (clear `known_hosts` for the camera); `authorized_keys` re-copied from the card |

Shared paths are in [Persistence and memory](README.md#persistence-and-memory).

Memory: with `lp_app` running and three ssh sessions open, each dropbear process used about 550 KB (`ps` on the device).

## Verified

On the camera:
- `dropbear -V` runs.
- With `start-sshd.sh` started by hand: the `mount --bind` over `/etc/passwd` works on the read-only rootfs, and root's home becomes `/userdata/ssh`.
- Pubkey login as root works (`Pubkey auth succeeded for 'root'`).
- Card layout installed: `/mnt/sdcard/bin/{dropbearmulti,rsync,start-sshd.sh,authorized_keys}`, with md5 matching the source. The hook block sits before `umount /mnt/sdcard` in the card's `lp_app.sh` (the `sdcard_no_rsync` variant). The original is saved as `/mnt/sdcard/lp_app.sh.bak-pre-sshd`.

On the host (qemu-user):
- Dropbear with pubkey auth and a remote command.
- `start-sshd.sh` in a sandbox: fresh install, key copy, idempotent rerun, restart after a binary change on the card. The daemon's cwd is `/` and it has no files open under the card directory.

Reboot (on the camera): after a power cycle the hook started dropbear on its own. `/mnt/sdcard/logs/dropbear.log` ended with `bound /userdata/ssh/passwd over /etc/passwd` and `started dropbear on port 22`, and the card came back mounted with `fmask=0000,dmask=0000`, so the hook's umount/remount still worked. The daemon ran with cwd `/` and nothing open on the card. `sync_loop.sh` and `lp_app` started as usual, and key login worked. To recheck after future changes:

```sh
ssh root@CAMERA_IP 'tail -5 /mnt/sdcard/logs/dropbear.log; tail -3 /tmp/dropbear.log; grep /mnt/sdcard /proc/mounts'
```

Telnet disabled (on the camera): with the `telnetd` line commented out in the card's `lp_app.sh`, after `sync; reboot -f` port 23 refused connections, no `telnetd` process ran, port 22 (dropbear) listened, and ssh key login worked.

If ssh doesn't come up, there is no telnet fallback. Take the card out and, on a PC, uncomment `telnetd` in `lp_app.sh`, or restore `lp_app.sh.bak-pre-notelnet` or `lp_app.sh.bak-pre-sshd`. Do not use `lp_stop` for this: it skips the whole hook, so neither ssh nor telnet starts. See [Target facts](README.md#target-facts).
