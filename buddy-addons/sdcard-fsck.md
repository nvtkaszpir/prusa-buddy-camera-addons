# sdcard-fsck (microSD check and repair at boot)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile) and
[Install via microSD](README.md#install-via-microsd).

## Why

The microSD card is vfat. `reboot -f`, power cuts and printer resets leave it dirty or with broken FAT chains,
lost clusters and bad directory entries. The boot hook mounts it with `errors=remount-ro`, so the first time
the kernel hits such an error the card silently becomes read-only: lp_app logs, uploaded files and everything
else written to `/mnt/sdcard` fail until someone repairs the card on a PC. The stock system has a `fsck`
wrapper but no `fsck.vfat`/`fsck.fat`, so nothing ever repairs it.

This add-on runs `fsck.fat -a` (automatic repair) on every boot, while the card is unmounted between the
hook's `umount` and its read-write `mount`, and then makes sure the card ends up mounted read-write.

## Artifact

| artifact | size | sha256 |
|---|---|---|
| `out/fsck.fat` | 103860 B | `ba52ccca2b2949b5a03dac062451affaefbf164a8c81e0e4228f229ff5cd7f42` |

```sh
./build-dosfstools.sh                             # -> out/fsck.fat
qemu-arm-static out/fsck.fat --help               # Usage: out/fsck.fat [OPTIONS] DEVICE
```

`fsck.fat` (FAT12/16/32 check and repair) from dosfstools 4.2, built by `build-dosfstools.sh` with
`--without-iconv` (no iconv in the static musl build), so short names in messages are shown in the default
codepage only. `mkfs.fat` and `fatlabel` are not built.

## Install

On the card:

```
/mnt/sdcard/bin/fsck.fat           <- out/fsck.fat
/mnt/sdcard/bin/sdcard-fsck.sh     <- device/sdcard-fsck.sh
```

```sh
cp out/fsck.fat device/sdcard-fsck.sh "$SD/bin/"
sync
```

Then edit `/mnt/sdcard/lp_app.sh` and replace these two lines with the block from
[device/fsck-hook.sh](device/fsck-hook.sh):

```sh
umount /mnt/sdcard
mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
```

The block sits right after the ssh server block ([device/sshd-hook.sh](device/sshd-hook.sh)) and right before
the http/https file server block ([device/httpd-hook.sh](device/httpd-hook.sh)), i.e. before
`/tmp/sync_loop.sh` starts lp_app. The tail of `lp_app.sh` then reads:

```sh
<ssh server block>                       # sh /mnt/sdcard/bin/start-sshd.sh
<microSD check block>                    # replaces umount + mount
<http/https file server block>           # sh /mnt/sdcard/bin/start-httpd.sh
cp /mnt/sdcard/sync_loop.sh /tmp/ ; /tmp/sync_loop.sh
```

If `sdcard-fsck.sh` is missing from the card (or cannot be read), the block runs the original `umount` and
`mount` lines, so boot behaves exactly as without the add-on. To disable the check, delete
`/mnt/sdcard/bin/sdcard-fsck.sh`.

### What happens at boot

1. The hook copies `bin/sdcard-fsck.sh` and `bin/fsck.fat` from the card to `/tmp`. If the card copy of
   `fsck.fat` cannot be read, it uses `/userdata/bin/fsck.fat` instead.
2. `sdcard-fsck.sh` runs from `/tmp` (cwd `/`), never from the card, and logs to `/tmp/sdcard-fsck.log`.
   It records the card's state before the check: mounted or not, `ro`/`rw` flag from `/proc/mounts`, and
   whether a test write works.
3. While the card is still mounted it refreshes the persistent fallback `/userdata/bin/fsck.fat` from
   `/mnt/sdcard/bin/fsck.fat` when their md5 differs. `/userdata` may be wiped by a firmware update; the next
   boot copies it again.
4. `sync`, then `umount /mnt/sdcard`, retried up to 5 times one second apart. If the card stays mounted (some
   process holds a file open on it), it does **not** run fsck on a mounted filesystem: it tries
   `mount -o remount,rw`, logs, and exits 1.
5. `timeout 600 fsck.fat -a -w DEV` (`-a` repairs without asking, `-w` writes each fix immediately). The device
   is the one `/mnt/sdcard` was mounted from, else `/dev/mmcblk1p1`. The 600 s limit only guards against a
   hang. If `fsck.fat` is missing it logs that and skips the check.
6. `mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro DEV /mnt/sdcard` (the hook's original
   options). If that fails twice it mounts read-only as a last resort, because the rest of `lp_app.sh` copies
   `sync_loop.sh` from the card.
7. It checks that the card is mounted `rw` and that a test file can be created and removed; if not, it tries
   `mount -o remount,rw` once.
8. It appends `/tmp/sdcard-fsck.log` to `/mnt/sdcard/logs/fsck.log` (creating `logs/`) once the card is
   writable. Exit status 0 means the card ended up mounted read-write; any other result exits 1 and the hook
   prints `sdcard-fsck.sh failed`.

Repaired lost cluster chains may be saved as `FSCK0000.REC`, `FSCK0001.REC`, ... in the card's root directory.

## Log

`/mnt/sdcard/logs/fsck.log` (all boots appended), and `/tmp/sdcard-fsck.log` (last boot only, also present when
the card could not be made writable). A clean boot looks like:

```
... sdcard-fsck: start: device /dev/mmcblk1p1, mount point /mnt/sdcard, fsck /tmp/fsck.fat
... sdcard-fsck: before: mounted /dev/mmcblk1p1 on /mnt/sdcard, mode rw, test write ok
... sdcard-fsck: running: timeout 600 /tmp/fsck.fat -a -w /dev/mmcblk1p1
fsck.fat 4.2 (2021-01-31)
/dev/mmcblk1p1: ... files, .../... clusters
... sdcard-fsck: fsck.fat exit 0: filesystem clean
... sdcard-fsck: after: mounted /dev/mmcblk1p1 on /mnt/sdcard, mode rw, test write ok
... sdcard-fsck: done: card mounted read-write
```

`fsck.fat` exit codes, as logged:

| exit | meaning |
|---|---|
| 0 | no errors found |
| 1 | errors corrected; also a fatal error such as an unreadable device or both FATs corrupt: read the output above it |
| 2 | usage error, filesystem not accessed |
| 124, 143 | killed by `timeout` after 600 s; the repair may be incomplete |
| 137 | killed by SIGKILL, most likely the kernel OOM killer; the repair may be incomplete |

Any other code means the filesystem was not repaired. In every case the script still mounts the card.

## Memory

`fsck.fat` keeps the FAT in RAM: during the check it holds both FAT copies plus a per-cluster owner table,
roughly 12 bytes per cluster on FAT32 (from the dosfstools 4.2 source). A 32 GB card with 32 KiB clusters has
about 1 M clusters, so about 12 MB. The camera has 34 MB RAM and only about 7 MB free once lp_app runs, which
is why the check runs in the boot hook before `sync_loop.sh` starts lp_app. Large cards or cards formatted with
small clusters need proportionally more; if `fsck.fat` is killed (exit 137), use a smaller card or reformat
with larger clusters (`mkfs.fat -F 32 -s 64` on a PC gives 32 KiB clusters with 512-byte sectors).
`fsck.fat` only handles FAT12/16/32, not exFAT.

Seen on the camera on 2026-11-08: the maintainer's 32 GB card has 16 KiB clusters (32 sectors per cluster,
about 1.95 M clusters, so about 23 MB). `fsck.fat -a -w` run from `/tmp` on the unmounted card, with lp_app and the
add-on daemons stopped, was killed with SIGKILL (exit 137), most likely by the OOM killer. This card has to be
checked on a PC or reformatted.

## Limitations

- If the card is so damaged that RkLunch cannot read `lp_app.sh` (or `bin/sdcard-fsck.sh`), the hook never
  runs this check; repair the card on a PC (`fsck.fat -a /dev/sdX1`).
- A run killed by `timeout` or the OOM killer may leave a partially repaired filesystem; the next boot checks
  it again.
- Anything that keeps a file open on the card before this block (e.g. a daemon started with its cwd or log on
  `/mnt/sdcard`) makes the `umount` fail, and the check is skipped. `start-sshd.sh` keeps nothing open there.

## Verified

On the host:
- `build-dosfstools.sh` output, `file out/fsck.fat`:
  `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, stripped`;
  `readelf -h`: `Type: EXEC`, `Flags: 0x5000400, Version5 EABI, hard-float ABI`.
- `qemu-arm-static out/fsck.fat -a -w` on a fresh 64 MB FAT16 image: exit 0.
- `sdcard-fsck.sh` under busybox 1.30.1 `sh`/`mount`/`umount`/`timeout` in a privileged container, with
  `SDCARD_MNT` pointing at a loop-mounted 64 MB image, `out/fsck.fat` via qemu-user:
  - image mounted `ro`, boot sector damaged: logged `mode ro, test write FAILED`, `fsck.fat` exit 1 (repaired),
    card remounted `rw`, test write ok, log appended to `logs/fsck.log`, script exit 0; fallback copy installed
    into `PERSIST_DIR`.
  - `FSCK=/nonexistent`: fsck skipped, card remounted, script exit 0.
  - a process with its cwd on the mount: 5 umount attempts failed, fsck not run, card left mounted `rw`,
    script exit 1.

Not yet run on the camera.
