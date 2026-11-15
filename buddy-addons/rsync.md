# rsync

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile), [Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet). Runs over ssh, so it needs [dropbear.md](dropbear.md).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/rsync` | rsync 3.5.1 + zlib 1.3.2, `build-rsync.sh` | rsync server and client, zlib compression | 518436 B | `2db919ff671d3f191f4475e0e096cee8e7951bd943d3e47d214ee18a1b4b7cbb` |

```sh
./build-rsync.sh                                  # -> out/rsync
qemu-arm-static out/rsync --version               # rsync 3.5.1, protocol 33, zlib
```

## Install

On the card:

```
/mnt/sdcard/bin/rsync              <- out/rsync
```

```sh
cp out/rsync "$SD/bin/"
sync
```

`start-sshd.sh` (see [dropbear.md](dropbear.md#what-happens-at-boot)) copies it to `/userdata/bin/` at boot when its md5 differs from the card's. Without the card, upload it as in [Upload via telnet](README.md#upload-via-telnet); the examples there use `rsync`.

## Use

rsync over ssh. **Always pass `--rsync-path=/userdata/bin/rsync`.** The camera's `/etc/profile` replaces PATH for login shells, so `rsync` would not be found otherwise.

```sh
rsync -av --rsync-path=/userdata/bin/rsync -e ssh ./local_dir/ root@CAMERA_IP:/userdata/somedir/
rsync -av --rsync-path=/userdata/bin/rsync -e ssh root@CAMERA_IP:/userdata/somedir/ ./local_dir/
```

Remote commands must not print extra output, because it corrupts the rsync stream. `dropbear` runs with `-m` (no motd). `/etc/profile` prints nothing on this camera.

## Verified

On the camera:
- `rsync --version` runs.
- rsync over ssh with `--rsync-path=/userdata/bin/rsync`: 300 KB push and pull, sha256 matching.

On the host (qemu-user):
- rsync over dropbear (push, pull, incremental), with sha256 matching.
