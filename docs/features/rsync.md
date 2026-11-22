# rsync

A static rsync 3.5.1 (with zlib) for the camera, so you can copy files to and from it with `rsync` over ssh.
It has no daemon and opens no port of its own. It runs over the [ssh](ssh.md) feature (dropbear).

## How it works

- `buddy-addons/build-rsync.sh` cross-compiles rsync 3.5.1 and zlib 1.3.2 into a static, stripped, non-PIE
  ARMv7 binary `buddy-addons/out/rsync`.
- You put the binary on the microSD card as `/mnt/sdcard/bin/rsync`.
- At boot, `start-sshd.sh` (started by the ssh hook in `/mnt/sdcard/lp_app.sh`) copies `dropbearmulti`, `rsync`
  and `drill` from the card to `/userdata/bin/`. It copies a file only when its md5 differs from the copy
  on the card.
- The copy in `/userdata/bin/rsync` stays there across reboots. Without a card you can upload it by hand
  as described in `buddy-addons/README.md` ("Upload via telnet").
- The camera's `/etc/profile` replaces `PATH` for login shells, so the remote side cannot find `rsync` by
  name. Always pass `--rsync-path=/userdata/bin/rsync`.
- dropbear runs with `-m` (no motd), so remote commands print nothing extra that would break the rsync stream.

## What to change

The binary needs no configuration. On your host, change only these values:

- **Camera address**: `Taskfile.yml`, var `CAMERA_HOST`, default `192.168.1.75`. Set it to your camera's IP.
  `task buddy:sync` uses it as `root@{{.CAMERA_HOST}}`. In the manual commands below, replace `CAMERA_IP`.
- **Remote rsync path**: `--rsync-path=/userdata/bin/rsync`, hard-coded in the `buddy:sync` task in
  `Taskfile.yml` and used in all examples. Change it only if you installed rsync somewhere else.
- **ssh access**: rsync uses the same login (root over dropbear, your authorized key) as the [ssh](ssh.md)
  feature. Set that up first.

!!! note
    rsync works only after the ssh feature is installed and dropbear is running.
    Without `--rsync-path=/userdata/bin/rsync`, the transfer fails because the remote side cannot find
    `rsync`.

## Build and deploy

```sh
cd buddy-addons
./build-rsync.sh                     # -> out/rsync
qemu-arm-static out/rsync --version  # optional host check: rsync 3.5.1, protocol 33
ADDONS=$PWD
cd /path/to/mounted/sdcard           # card root
cp "$ADDONS/out/rsync" bin/
sync
```

Put the card back in the camera and reboot it. `start-sshd.sh` then installs `/userdata/bin/rsync`.

`task buddy:sync` uses rsync itself to push the staged payload to `/mnt/sdcard/bin/`. It does **not** copy the
rsync binary itself, so you have to install rsync by hand first.

## Verify

On the camera (over ssh):

```sh
/userdata/bin/rsync --version
```

From the host, fetch or push files (replace the placeholder paths with your own):

```sh
# fetch a directory from the camera
rsync -av --rsync-path=/userdata/bin/rsync -e ssh root@CAMERA_IP:/userdata/somedir/ ./local_dir/
# fetch timelapse images from the card (written by lp_app)
rsync -av --rsync-path=/userdata/bin/rsync -e ssh root@CAMERA_IP:/mnt/sdcard/timelapse/ ./timelapse/
# fetch lp_app logs (hook runs: lp_app --noshell --log2file /mnt/sdcard/logs)
rsync -av --rsync-path=/userdata/bin/rsync -e ssh root@CAMERA_IP:/mnt/sdcard/logs/ ./logs/
# push to the camera
rsync -av --rsync-path=/userdata/bin/rsync -e ssh ./local_dir/ root@CAMERA_IP:/userdata/somedir/
```

For where these card paths come from, see [lp_app](../findings/cam-3.1.3/oem/usr/sbin/lp_app.md).

## Timelapse tasks

`lp_app` writes each print's timelapse to the card as `timelapse/<job>.avi` (the video) and
`timelapse/<job>/<YYYYMMDD>/timelapse_*.jpg` (the photos), see [Video](../findings/video.md). From the repo root:

```sh
task buddy:timelapse:avi -- --progress -W   # videos -> downloads/timelapse/<job>.avi (recommended options)
task buddy:timelapse:jpg -- --progress -W   # photos -> downloads/timelapse/<job>/<YYYYMMDD>/*.jpg
task buddy:timelapse:avi -- -n              # dry run; anything after "--" goes to rsync
task buddy:timelapse:avi -- --progress -W --exclude=unknown_timelapse.avi   # skip the video being recorded
task buddy:timelapse:mp4                    # downloaded photos -> downloads/timelapse/<job>.mp4 (H.264)
task buddy:timelapse:clean -- -n            # list what the cleanup would delete
task buddy:timelapse:clean                  # asks, then deletes; --yes skips the question
```

!!! tip "Recommended: `-- --progress -W`"
    `-W` (`--whole-file`) sends changed files whole instead of running rsync's delta algorithm, which makes the
    camera's single slow core read and checksum its copy of the file first. When the host already has an older
    or partial copy (e.g. a video downloaded mid-print, or one kept by `--partial`), it roughly doubles the speed
    (0.75–0.81 → 1.48–1.54 MB/s, see [Transfer speed](#transfer-speed)); for a file the host does not have yet
    it makes no difference. `--progress` shows the transfer of each file. The trade-off: with `-W`, an interrupted
    download is sent again from the start instead of only its missing part.

- `TIMELAPSE_LOCAL` (default `downloads/timelapse`, gitignored) is the host directory; `CAMERA_HOST` and
  `SSH_OPTS` as for the other tasks. Both download tasks use `rsync -rt --partial`: files whose size and time
  match are skipped, and without `-W` an interrupted video download continues on the next run. The copies get
  mode 644/755.
- A video that is still being recorded is copied as it is at that moment; the next run updates it. Its AVI index
  is written at the end of the print, so play only finished videos (listed as `<job>.avi:D` in
  `timelapse/.timelapse_videos.csv`).
- Listing photos on the card is slow: on 2026-11-14, during a print, `ls` of a 318-photo day folder took 20 s,
  and a folder of the running print (about 12000 photos) did not finish in 10 minutes. rsync must stat each
  photo before copying it, so `buddy:timelapse:jpg` can sit at `receiving incremental file list` for a long
  time. It does not use `-m`, which would make the camera list the whole tree before sending anything; empty
  folders are deleted on the host afterwards. Exclude the job being recorded, e.g.
  `task buddy:timelapse:jpg -- --exclude=unknown_timelapse/`, or download photos when the printer is idle.
  For times and out-of-memory kills when downloading whole jobs, see
  [Timelapse downloads: real jobs](#timelapse-downloads-real-jobs).
- `buddy:timelapse:mp4` turns the downloaded photos of each job into `TIMELAPSE_LOCAL/<job>.mp4` on the host:
  H.264 (libx264, `yuv420p`, `+faststart`), which browsers play, unlike the camera's MJPEG `.avi` (see
  [Video](../findings/video.md)). The photos are used in name order, so the day folders and the times in the
  file names give the order. Settings: `TIMELAPSE_FPS` (default `10`, the camera AVI's rate), `TIMELAPSE_CRF`
  (default `23`; lower is better and bigger), `TIMELAPSE_PRESET` (default `medium`), `TIMELAPSE_JOB` (one job
  only), and extra ffmpeg output options after `--`:

    ```sh
    task buddy:timelapse:mp4 TIMELAPSE_JOB=<job> TIMELAPSE_FPS=30 -- -vf scale=1280:-2   # 720p, 30 fps
    task buddy:timelapse:mp4 FFMPEG=/opt/ffmpeg/bin/ffmpeg         # a specific ffmpeg
    D='docker run --rm -u $(id -u):$(id -g) -v $PWD:$PWD -w $PWD --entrypoint ffmpeg'   # ffmpeg from docker
    task buddy:timelapse:mp4 FFMPEG="$D linuxserver/ffmpeg:8.0.1"
    ```

  It needs an ffmpeg with the `libx264` encoder (`ffmpeg -encoders | grep libx264`). Without `FFMPEG` it uses
  the first of `ffmpeg` on `PATH`, `/usr/bin/ffmpeg` and `/usr/local/bin/ffmpeg` that has libx264, and stops
  before doing anything if none has (or if the `FFMPEG` you set has none). It only makes MP4 files that do not
  exist yet: an existing `<job>.mp4` is skipped and never overwritten, even if more photos were downloaded since.
  Delete the MP4 to rebuild it. The MP4 is written as `<job>.mp4.part.mp4` first and renamed when ffmpeg
  succeeds, so an interrupted run leaves no MP4 behind. Tested on 2026-11-14 with the 2
  photos of a finished job and a 40-photo job spread over two day folders: 1920x1080 H.264 High at 10 fps, 2
  and 40 frames; with the docker image and `-- -vf scale=1280:-2`, 1280x720. Without `FFMPEG` the task picked
  `/usr/bin/ffmpeg` on the maintainer's host, whose `/usr/local/bin/ffmpeg` (first on `PATH`) has no libx264.
- The camera has only 1–6 MB of free RAM while `lp_app` runs. Both download tasks and the cleanup set
  `oom_score_adj` to 1000 on the camera, so if memory runs out the kernel kills them, not `lp_app`. On
  2026-11-14 a long `find | sort` over the photo folders (run by hand, without this setting) got `lp_app`
  killed by the OOM killer. `sync_loop.sh` started it again, but the timelapse of the running print stopped.
- `buddy:timelapse:clean` runs `buddy-addons/device/timelapse-clean.sh` on the camera. It deletes every
  `<job>.avi` and `<job>/` folder, except for a job that a process (`lp_app`) still has a file open in, i.e. the
  print being recorded. It keeps the `timelapse/` directory itself (`lp_app` does not recreate it) and removes the
  lines of deleted videos from `.timelapse_videos.csv`. It does not check that you downloaded anything first.
  A recording that stopped without finishing (for example after `lp_app` was killed) has no open file, so it
  counts as finished and is deleted too; run `-- -n` first.

## Transfer speed

Measured on 2026-11-14 on the maintainer's camera (firmware 3.1.3, Wi-Fi, `lp_app` running, no other transfer,
load average 9–11 throughout, about 9 with nothing transferring). Each run copied the same 22,405,967-byte
`lp_app` log from the card to a host on the LAN; every copy was compared with a reference copy and matched.
rsync used the `oom_score_adj` wrapper of the tasks. HTTP and HTTPS used a temporary lighttpd config without
basic auth and with plain HTTP on 8080; the normal config was restored afterwards.

| method | encryption | MB/s (run 1, run 2) |
|---|---|---|
| `wget http://CAMERA:8080/...` (lighttpd) | none | 5.02, 5.04 |
| `curl https://CAMERA:8443/...`, TLS 1.3 forced to ChaCha20-Poly1305 | ChaCha20-Poly1305 | 1.84 (1 run) |
| `rsync -t`, new file | ssh, chacha20-poly1305 (default) | 1.62, 1.75 |
| `rsync -t -W`, new file | ssh, chacha20-poly1305 | 1.68, 1.39 |
| `rsync -t -W`, host has the first half of the file | ssh, chacha20-poly1305 | 1.54, 1.48 |
| `curl https://...`, TLS 1.3 forced to AES-128-GCM | AES-128-GCM | 1.24 (1 run) |
| `wget https://CAMERA:8443/...` (lighttpd default) | AES-256-GCM | 1.11, 1.18 |
| `rsync -t -W`, new file, `ssh -c aes128-ctr -m hmac-sha2-256` | aes128-ctr | 1.06, 1.12 |
| `rsync -t`, host has the first half of the file | ssh, chacha20-poly1305 | 0.75, 0.81 |

- The camera's single Cortex-A7 core is the limit, not the card (reading the same kind of file on the camera
  runs at about 7 MB/s) or the network: unencrypted HTTP is about three times as fast as anything encrypted.
- ChaCha20-Poly1305 is the fastest cipher, for ssh and for TLS: the CPU has no AES instructions. ssh already
  picks it by default. lighttpd's TLS 1.3 default is AES-256-GCM, the slowest; a client can ask for ChaCha20
  (`curl --tls13-ciphers TLS_CHACHA20_POLY1305_SHA256`).
- `-W` halves the time when the host already has a partial or older copy; for new files it makes no difference
  (the two "new file" rows overlap).
- Measured with one 22 MB file. Copying many small photos adds the slow listing on the card on top.

!!! warning "Plain HTTP without a password serves the whole card to the network"
    The fastest setup, HTTP without basic auth, is what the shipped `lighttpd.conf` uses since 2026-11-14 (the
    measurement above still had HTTPS on 8443 as well, and served `logs/`). It lets anyone on the network read
    every file lighttpd serves. The `lp_app` logs in `logs/` can contain the Prusa Connect token and Wi-Fi
    credentials (see [lp_app](../findings/cam-3.1.3/oem/usr/sbin/lp_app.md)), so the shipped config denies
    `logs/` (and the card's `userdata/`). See [HTTPS](https.md#what-to-change) to turn TLS and auth back on. A
    middle ground is to serve only the timelapses (`server.document-root = "/mnt/sdcard/timelapse"`). Then, for
    example:

    ```sh
    wget -c http://CAMERA_IP:8080/timelapse/<job>.avi   # whole card served; -c continues a broken download
    wget -c http://CAMERA_IP:8080/<job>.avi             # with document-root /mnt/sdcard/timelapse
    ```

### Timelapse downloads: real jobs

Measured on 2026-11-22 on the maintainer's camera (firmware 3.1.6, Wi-Fi) with
`task buddy:timelapse:jpg -- -W`, i.e. rsync over ssh (chacha20-poly1305) with the `oom_score_adj` 1000 wrapper.
The photos are 1920x1080 JPEG, one every 10 s (`snapshot_upload_interval=10000`, in ms, in `xhr_config.ini`).

Photos:

| job | recorded | photos | size | per photo | download | conditions |
|---|---|---|---|---|---|---|
| A | 50.6 h | 17,693 | 3.52 GB | 199 KB | run 1: 5,121 photos, 1.00 GB, 12 min 44 s, then OOM kill | `lp_app` runs |
| A, rest | | 12,572 | 2.52 GB | | run 2: 14 min 57 s, incl. a 4 min stall | `lp_app` stopped |
| B | 20.5 h | 7,134 | 1.40 GB | 196 KB | not timed; about 18 min or 6 min [INFERENCE] | as runs 1 and 2 |

- Job A, `adapters_v6_x9_0_4n_0_2mm_PLA_COREONEL_2h37m_bgc`: 3,515,824,642 bytes (3.3 GiB on the host),
  from 2026-11-20 11:28:20 to 2026-11-22 14:04:34. Day folders `20261120` 4,407 photos, `20261121` 8,343
  (a whole day, one photo every 10.36 s), `20261122` 4,943. Run 1 averaged about 1.31 MB/s (6.7 photos/s);
  run 2, after its stall, about 3.9 MB/s (19 photos/s) for about 11 minutes.
- Job B, `unknown_timelapse` (recorded on firmware 3.1.3): 1,398,924,143 bytes, from 2026-11-13 23:06:17 to
  2026-11-14 19:36:28. Day folders `20261113` 318 photos, `20261114` 6,816. The estimate is 1.40 GB at
  1.3 MB/s (`lp_app` running, if it is not OOM-killed) or at 3.9 MB/s (`lp_app` stopped).

Videos (MJPEG 1920x1080, 10 fps; the AVI holds the same JPEG frames plus about 16 bytes of index per frame,
see [Video](../findings/video.md)):

| file | recorded | frames | video | size | MP4 | download |
|---|---|---|---|---|---|---|
| `unknown_timelapse.avi` (job B) | 20.5 h | 7,040 | 713.3 s | 1.38 GB | 477 MB | not timed; 4.6–15 min [INFERENCE] |
| `octopus_magnets_..._7h17m_bg.avi` | about 12.9 h [INFERENCE] | 4,633 | 463.3 s | 1.21 GB | – | upload: 799 s |

- `unknown_timelapse.avi`: 1,380,185,753 bytes. `task buddy:timelapse:mp4` turned it into a 477,159,158-byte
  H.264 MP4 (713.4 s), about a third of the size.
- `octopus_magnets_0_4n_0_2mm_PLA_COREONEL_7h17m_bg.avi`: a print estimated at 7 h 17 min, 1,206,392,590
  bytes. Its 4,633 frames x 10 s give about 12.9 h of recording [INFERENCE]. Uploading it with rsync over ssh
  took 799 s (about 1.5 MB/s) with `lp_app` running.
- No AVI was on the card on 2026-11-22, so no AVI download was timed. [INFERENCE] An AVI is one large file:
  no listing and no file list in memory. For the 1.38 GB video, the measured rates give about 13–15 min with
  rsync and `lp_app` running (1.5–1.75 MB/s), about 6 min with `lp_app` stopped (3.9 MB/s), and about 4.6 min
  with `wget` over plain HTTP (5 MB/s, `lp_app` running, see the table above).

Findings:

- **Recording time, not print time, sets the size.** Job A's slicer estimate is 2 h 37 min (about 940 photos,
  190 MB at 10 s), but its photos cover 50.6 h: firmware 3.1.3 kept taking photos after the print ended until
  `lp_app` was restarted (the last photo is from the reboot for the firmware update). [INFERENCE] 3.1.3 has no
  printer-state handling; 3.1.6/3.1.7 add printer state.
- **Rule of thumb**: 360 photos per hour of recording, about 70 MB per hour (199 KB x 360) for the photos and
  about the same for the AVI, and 36 s of video per hour at 10 fps.
- **OOM with `lp_app` running.** On 3.1.6 with `lp_app` running the camera had about 1.2–1.4 MB free
  (3.5–5.8 MB free+cache). Run 1 ended when the kernel OOM killer killed the camera-side rsync
  (`Out of memory: Killed process ... (rsync) ... anon-rss:1680kB ... oom_score_adj:1000`).
  Retries died quickly while rsync built the file list of the 8,343-photo folder, and `ls -l` of that folder did
  not finish in 5 minutes. vfat looks up names linearly, so stat-ing every file of a folder with about 10,000
  entries grows quadratically.
- **Stopping `lp_app` frees memory and CPU.** With `lp_app` and `sync_loop.sh` stopped, about 15.7 MB was
  available and the transfer finished. The camera is offline meanwhile (no video, no Connect); Wi-Fi stays up
  (`wpa_supplicant`). In 5-minute samples it moved 4,695 photos / 913 MB (about 3.0 MB/s) and then
  6,301 photos / 1,208 MB (about 4.0 MB/s), about twice the 1.6–1.75 MB/s of the table above. [INFERENCE] The
  single core is then free for ssh encryption. The first ~4 minutes were lost to leftover `ls` processes on the
  camera that competed for the card.
- **Verified.** A dry run afterwards, `task buddy:timelapse:jpg -- -n -i`, listed no file to transfer (no `>f`
  lines) and took about 5 minutes (listing only); the local total matched rsync's total size exactly
  (rsync reported `speedup is 1.40` for run 2, on 3.52 GB total).

Recommendations:

- Download photo folders while the printer is idle. With day folders of thousands of photos, expect the
  camera-side rsync to be OOM-killed while `lp_app` runs on 3.1.6. Running the task again resumes where it
  stopped, but if listing a folder itself dies every time, the only fix today is to stop `lp_app` for the
  transfer, or to download the AVI instead.
- Choose by need: the AVI is one file, so there is no listing and no file list in memory, and it downloads
  fastest; the photos are the single frames, for re-encoding at other frame rates (`buddy:timelapse:mp4`).
- Delete from the camera with `task buddy:timelapse:jpg -- --remove-source-files`: rsync removes only the files
  it confirmed as transferred or identical on the host. For job A (17,693 photos, all already on the host,
  `lp_app` stopped) this took 3 min 41 s. It leaves the empty day and job folders behind; `buddy:timelapse:clean`
  removes them afterwards.

## Source files

- `buddy-addons/rsync.md`
- `buddy-addons/build-rsync.sh`
- `buddy-addons/device/start-sshd.sh`
- `buddy-addons/device/sshd-hook.sh`
- `buddy-addons/README.md`
- `buddy-addons/device/timelapse-clean.sh`
- `Taskfile.yml`
