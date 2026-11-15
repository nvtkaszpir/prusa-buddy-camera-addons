# microSD check and repair at boot (sdcard-fsck)

On every boot the camera unmounts the vfat microSD card, checks and repairs it with `fsck.fat -a`
(dosfstools 4.2), then mounts it read-write again and checks that it can be written to. The stock system has
a `fsck` wrapper but no `fsck.vfat`/`fsck.fat`, so a dirty card was never repaired.

## How it works

Why it is needed: `reboot -f`, power cuts and printer resets leave the card dirty or with broken FAT chains.
The boot hook mounts the card with `errors=remount-ro`, so the first time the kernel hits such an error the card
silently becomes read-only. After that, lp_app logs, uploads and every other write to `/mnt/sdcard` fail.

Files on the card:

- `/mnt/sdcard/bin/fsck.fat`: static ARM binary from `out/fsck.fat`.
- `/mnt/sdcard/bin/sdcard-fsck.sh`: the check script from `device/sdcard-fsck.sh`.
- The block from `device/fsck-hook.sh`, pasted into the boot hook `/mnt/sdcard/lp_app.sh`. It replaces the
  hook's original `umount /mnt/sdcard` and `mount -t vfat ...` lines. It goes right after the ssh block and
  before the httpd block, so it runs before `/tmp/sync_loop.sh` starts lp_app.

What happens at boot:

1. The hook copies `bin/sdcard-fsck.sh` and `bin/fsck.fat` to `/tmp`. If the card copy of `fsck.fat` cannot be
   read, it uses `/userdata/bin/fsck.fat` instead. If `sdcard-fsck.sh` is missing, the original `umount` and
   `mount` lines run, so boot behaves as it would without the add-on.
2. The script runs from `/tmp` (cwd `/`), never from the card. It logs the card's state before the check:
   mounted or not, `ro`/`rw`, and whether a test write works.
3. While the card is still mounted, it refreshes the persistent fallback `/userdata/bin/fsck.fat` if its md5
   differs from the card copy. `/userdata` may be wiped by a firmware update, and the next boot copies it again.
4. `sync`, then `umount /mnt/sdcard`, tried up to 5 times one second apart. If the card stays mounted, fsck is
   **not** run: the script tries `mount -o remount,rw` and exits 1.
5. `timeout 600 fsck.fat -a -w DEV`: `-a` repairs without asking and `-w` writes each fix immediately. `DEV` is
   the device `/mnt/sdcard` was mounted from, else `/dev/mmcblk1p1`. The script uses the busybox `timeout -t`
   form or the plain form, whichever works, and runs without a timeout if there is no `timeout` applet. If
   `fsck.fat` is missing or not executable, the check is skipped.
6. `mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro DEV /mnt/sdcard`. These are the hook's
   original options. If the mount fails twice, the script mounts read-only as a last resort, because the rest of
   `lp_app.sh` copies `sync_loop.sh` from the card.
7. If the card is not mounted `rw`, or a test file cannot be created, it tries `mount -o remount,rw` once.
8. When the card is writable, it appends `/tmp/sdcard-fsck.log` to `/mnt/sdcard/logs/fsck.log`. Exit 0 means the
   card ended up mounted read-write. Otherwise the hook prints `sdcard-fsck.sh failed, see /tmp/sdcard-fsck.log`.

Settings that reduce corruption: the add-on does not change mount options or sysctls. It keeps the original
`errors=remount-ro` mount and makes sure each boot starts from a repaired, read-write card. It also calls `sync`
before unmounting and after writing the log. No network ports are used.

Logs:

- `/mnt/sdcard/logs/fsck.log`: all boots appended.
- `/tmp/sdcard-fsck.log`: last boot only. It also exists when the card could not be made writable.
- Recovered lost cluster chains may appear as `FSCK0000.REC`, `FSCK0001.REC`, ... in the card's root directory.

`fsck.fat` exit codes in the log: `0` clean; `1` errors corrected, or a fatal error (read the output above it);
`2` usage error; `124`/`143` killed by the timeout; `137` killed, most likely by the OOM killer. In every case
the script still mounts the card.

Memory: `fsck.fat` keeps the FAT in RAM, roughly 12 bytes per cluster on FAT32. That is about 12 MB for a 32 GB
card with 32 KiB clusters. The camera has 34 MB RAM and only about 7 MB free once lp_app runs, which is why the
check runs before lp_app starts. `fsck.fat` handles FAT12/16/32 only, not exFAT.

!!! warning "Check your card's cluster size"
    The maintainer's 32 GB card has 16 KiB clusters (about 1.95 million clusters, so about 23 MB). On 2026-11-08 a
    run on the camera, with `lp_app` and the add-on daemons stopped, was killed with SIGKILL (exit 137), most
    likely by the OOM killer. This feature cannot check such a card; check it on a PC or reformat it with 32 KiB
    clusters (`mkfs.fat -F 32 -s 64`, erases the card). The cluster size is in the boot sector:
    `ssh root@CAMERA_IP 'dd if=/dev/mmcblk1p1 bs=512 count=1 2>/dev/null' | od -An -tu1 -j13 -N1` prints the
    sectors per cluster (64 = 32 KiB with 512-byte sectors).

## What to change

Nothing is required. The defaults match the stock boot hook. The script reads every setting below from the
environment, so you can override it by prefixing the `sh /tmp/sdcard-fsck.sh` call in the hook block.

- `device/sdcard-fsck.sh`, `SDCARD_DEV`: defaults to the device currently mounted on `SDCARD_MNT`, else
  `/dev/mmcblk1p1`. Set it only if your card is on a different partition.
- `device/sdcard-fsck.sh`, `SDCARD_MNT`, default `/mnt/sdcard`: set it only for a test run against another
  mount point, such as a loop-mounted image on a PC.
- `device/sdcard-fsck.sh`, `MOUNT_OPTS`, default `rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro`: keep it
  in sync if your `lp_app.sh` variant mounts the card with different options.
- `device/sdcard-fsck.sh`, `FSCK_TIMEOUT`, default `600` (seconds): raise it for large or slow cards that time
  out (exit 124/143).
- `device/sdcard-fsck.sh`, `FSCK`: defaults to `fsck.fat` next to the script, else `/tmp/fsck.fat`. The fsck
  flags `-a -w` are hard-coded in the script.
- `device/sdcard-fsck.sh`, `PERSIST_DIR`, default `/userdata/bin`: set it to empty to disable the fallback copy.
- `device/sdcard-fsck.sh`, `LOG`, default `/tmp/sdcard-fsck.log`.
- `/mnt/sdcard/lp_app.sh`: you must paste the `device/fsck-hook.sh` block in by hand, in place of the original
  `umount` and `mount` lines. In the `8/` variant, it goes right after the ssh block, before the final
  `lp_app` line.
- To disable the check, delete `/mnt/sdcard/bin/sdcard-fsck.sh`.

!!! warning "Risks"
    - The script never runs fsck on a mounted filesystem. If any process keeps a file open on the card before
      this block (for example a daemon with its cwd or log on `/mnt/sdcard`), `umount` fails and the check is
      skipped. Do not start such daemons before this block.
    - A run killed by the timeout or by the OOM killer (exit 137) may leave a partially repaired filesystem.
      The next boot checks it again. If the OOM killer stops it, use a smaller card or reformat it with larger
      clusters on a PC (`mkfs.fat -F 32 -s 64`). Reformatting erases the card.
    - `fsck.fat -a` repairs automatically. Lost data may end up only in `FSCK*.REC` files.
    - If the card is too damaged for RkLunch to read `lp_app.sh`, this check never runs. Repair the card on a PC
      with `fsck.fat -a /dev/sdX1`.

## Build and deploy

```sh
cd buddy-addons
./build-dosfstools.sh                    # -> out/fsck.fat
qemu-arm-static out/fsck.fat --help      # optional check on the host
```

Copy the files to the card by hand, from `buddy-addons/`:

```sh
ADDONS=$PWD
cd /path/to/mounted/sdcard               # card root
cp "$ADDONS/out/fsck.fat" "$ADDONS/device/sdcard-fsck.sh" bin/
sync
```

Or over ssh from the repo root: `task buddy:sync`. It runs `buddy:stage`, which stages `out/fsck.fat` and the
`device/` scripts, then rsyncs them to `/mnt/sdcard/bin/` on `CAMERA_HOST` (default `192.168.1.75`). Hook files
(`*-hook.sh`) are not synced, so you still have to edit `lp_app.sh` by hand once.

## Verify

After a reboot, on the camera:

```sh
cat /tmp/sdcard-fsck.log           # last boot; ends with "done: card mounted read-write"
tail -n 20 /mnt/sdcard/logs/fsck.log
grep /mnt/sdcard /proc/mounts      # options should include rw
ls /mnt/sdcard/FSCK*.REC           # recovered chains, if any
```

## Source files

- `buddy-addons/sdcard-fsck.md`
- `buddy-addons/build-dosfstools.sh`
- `buddy-addons/device/sdcard-fsck.sh`
- `buddy-addons/device/fsck-hook.sh`
- `buddy-addons/README.md`
- `Taskfile.yml`
