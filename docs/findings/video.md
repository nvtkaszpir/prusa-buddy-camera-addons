# Video: timelapse files, AVI to MP4 conversion, and encoder hardware

What the camera's timelapse videos are, whether they can be turned into MP4 files (on the camera or elsewhere), and what video hardware the camera has. Checked on the running camera (firmware 3.1.3, 192.168.1.75) on 2026-11-01, with the add-ons from `buddy-addons/` installed (ssh, lighttpd). The on-camera tests were run while `lp_app` was running normally, without a print in progress.

## Summary

- The timelapse `.avi` is an AVI 1.0 file of 1920x1080 JPEG frames (MJPEG) at 10 fps. The frames are the same JPEG photos that `lp_app` saves next to it.
- Repacking it into MP4 or MOV without re-encoding works (ffmpeg `-c copy`), but the result is still MJPEG. VLC, mpv and QuickTime (MOV) play it; browsers do not. The file size does not change.
- A browser-playable MP4 needs H.264, i.e. decoding every JPEG and encoding it again.
- The SoC has a hardware H.264/H.265 encoder (RKVENC) and no hardware video or JPEG decoder. `lp_app` already uses the encoder for its RTSP stream.
- On the camera, with `lp_app` running, **no conversion fits in memory**. A process gets about 3–4 MB before the kernel's out-of-memory killer acts. Even a plain repack was killed. Only reading the file worked.
- Practical route: convert on a host after mirroring the card (wget/rsync), or record H.264 from the RTSP stream on a host.

## Hardware

| item | value | source |
|---|---|---|
| SoC | Rockchip RV1103G: device tree `rockchip,rv1103g-evb-v10`, `rockchip,rv1103`; model "Rockchip RV1103G EVB V10 Board" | `/proc/device-tree/compatible`, `model` |
| CPU | 1 core, ARMv7 Cortex-A7 (`ARMv7 Processor rev 5`), NEON, VFPv4, hardware integer divide | `/proc/cpuinfo` |
| RAM | 16384 pages = 64 MB. 6144 pages (24 MB) are CMA (reserved for camera/ISP/encoder buffers) and 7802 pages in total are reserved, leaving 34,328 kB managed by Linux. No swap | OOM report in `dmesg`, `/proc/meminfo` |
| video encoder | one device, `RKVENC`, `HW_ID 0x50603313`, driven by the `mpp_vcodec` kernel module (used by `rockit`). `/proc/mpp_service/supports-device` lists only `RKVENC` | `/proc/mpp_service/*`, `lsmod` |
| video decoder | none: the kernel offers no decoder device, and there is no JPEG decode block | `/proc/mpp_service/supports-device` |
| 2D engine | `rga3` (scaling, colour conversion), used by `rockit` | `lsmod`, `/dev/rga` |
| encoder use | two encoder sessions open, presumably both `lp_app`'s (the only process using `rockit`) [INFERENCE] | `/proc/mpp_service/sessions-summary` |
| RTSP stream | `rtsp://<camera>:554/live` is H.264 Constrained Baseline, 1920x1080, 25 fps | `ffprobe` from a host |

The index page calls the SoC "RV1106-class". The device tree of this unit says RV1103 (RV1103G). The RV1103 and RV1106 belong to the same Rockchip family, which matches the RV1106/RV1103 SDK samples on the firmware.

From [`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md): VENC 0 is JPEG (1920x1080, used for snapshots and timelapse photos), VENC 1 is the H.264 stream. Rockchip's [`mpi_enc_test`](cam-3.1.3/oem/usr/bin/mpi_enc_test.md) feeds the encoder raw frames (YUV/RGB file, V4L2, or a test pattern). The encoder cannot take JPEG input.

Memory at rest (`lp_app` running): `MemAvailable` about 6.3 MB, `MemFree` about 2 MB, `lp_app` RSS 11–13 MB, slab 8.6 MB. The kernel's low watermark is `min:2392kB`, so about 3–4 MB is really available to a new process.

## Timelapse files on firmware 3.1.3

On the card, a print's timelapse is stored as:

```
/mnt/sdcard/timelapse/.timelapse_videos.csv            # e.g. "<job>.avi:D"
/mnt/sdcard/timelapse/<job>.avi                         # the video
/mnt/sdcard/timelapse/<job>/<YYYYMMDD>/timelapse_<HH-MM-SS-mmm>.jpg   # the photos
```

- The 3.1.3 build assembles a video. The analysed dump build (3.1.0) stored only JPEG stills, with a different file-name pattern (see [`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md#snapshots-and-timelapse)).
- `.timelapse_videos.csv` lists `<job>.avi:D`. `D` probably means done; only one entry was seen, so this is not confirmed.
- In a two-frame example, the `.avi` was 227,992 bytes and its two JPEGs 115,730 + 111,974 bytes. The AVI is the photos plus about 290 bytes of AVI structure.

Format of a long example (`octopus_magnets_0_4n_0_2mm_PLA_COREONEL_7h17m_bg.avi`, from a 7 h 17 min print):

| property | value |
|---|---|
| size | 1,206,392,590 bytes |
| frames | 4,633 at 10 fps = 463.3 s |
| codec | MJPEG, FourCC `MJPG`, 1920x1080, `yuvj420p`, about 20.8 Mbit/s, about 260 KB per frame |
| structure | one `RIFF AVI ` chunk: `hdrl` (`avih`, one `strl`), `movi` with `00dc` chunks (each a complete JPEG starting `FF D8`), and an `idx1` index at the end (74,128 bytes = 16 bytes per frame) |
| OpenDML | none (no `indx`/`odml`), even though the file is over 1 GB |

The index is written at the end of the file, so an `.avi` from a print that is still running has no `idx1` yet.

## Converting to MP4

### Repack without re-encoding

```sh
ffmpeg -i in.avi -c copy out.mp4    # stream tag mp4v (MPEG-4 object type JPEG)
ffmpeg -i in.avi -c copy out.mov    # stream tag jpeg (QuickTime)
```

Both keep every JPEG frame, and the size is the same as the AVI (228 KB in, 228 KB out for the two-frame example). VLC, mpv and ffplay play both; QuickTime plays the MOV. Browsers do not: headless Chromium returned `""` for `canPlayType('video/mp4; codecs="mp4v.6C"')` and never loaded the file's metadata. So a repack only changes the container.

### Re-encode to H.264

Only H.264 (or H.265/AV1, with browser-dependent support) gives a file that browsers play and that is much smaller than MJPEG. That needs every JPEG decoded to raw pixels (about 3 MB per 1080p frame in 4:2:0) and encoded again. On a host this is a single command, for example:

```sh
ffmpeg -i in.avi -c:v libx264 -crf 23 -pix_fmt yuv420p -movflags +faststart out.mp4
```

## Test on the camera

### Build

`buddy-addons/build-ffmpeg.sh` builds a static, stripped ffmpeg 9.0.2 and ffprobe with libx264 (x264 `stable` at commit `b35605ac`), for ARMv7 hard-float, non-PIE. The tarball checksums are pinned, and the ffmpeg tarball's GPG signature was checked. The build contains only the AVI/MOV/image2/MJPEG demuxers, the MP4/MOV/null muxers, the MJPEG/H.264 decoders, the libx264 encoder, and a few filters. Each binary is about 4.3 MB (`ffmpeg` 4,437,760 bytes, `ffprobe` 4,245,192 bytes). Under qemu it encoded H.264 and stream-copied MJPEG correctly.

x264's ARM assembly files need the C preprocessor, so its `configure` must get `AS=<cross>-gcc` (the cross `as` rejects `-DSTACK_ALIGNMENT`).

### Transfer and card speed

| step | result |
|---|---|
| upload of the 1.2 GB AVI with rsync over ssh (Wi-Fi) | 799 s, about 1.5 MB/s |
| `md5sum` of the 1.2 GB file on the camera | 61 s, about 20 MB/s card read; md5 matched the host |
| ffmpeg reading and demuxing 600 frames (`-c copy -f null`) | 9 s, about 67 frames/s, about 17 MB/s |

### Method

ffmpeg ran from the card with `oom_score_adj` set to 1000, so that the kernel's out-of-memory (OOM) killer picks it rather than `lp_app`. A shell loop sampled every 2 s: ffmpeg's peak RSS (`VmHWM`), its CPU time (`/proc/<pid>/stat`), free + buffers + cache, `lp_app`'s RSS, and system idle time.

### Results (with `lp_app` running)

| test | outcome | ffmpeg peak RSS | min. free + cache | system idle |
|---|---|---|---|---|
| read + demux 600 frames, no output (`-c copy -f null`) | finished in 9 s | 2.5 MB | 5.6 MB | 6% |
| repack whole file to MP4 (`-c copy`) | **killed** after 75 s, 158 MB written | 4.0 MB | 2.7 MB | 3% |
| repack 600 frames to MP4 | **killed** after 123 s, 92 MB written | 4.2 MB | 2.3 MB | 1% |
| repack 600 frames, fragmented MP4 (`frag_keyframe+empty_moov`) | **killed** after 65 s | 4.3 MB | 2.6 MB | 3% |
| decode 30 frames to raw (`-f null`) | **killed**; 4.6 MB anonymous memory when killed | – | 5.8 MB | 5% |
| H.264 ultrafast, 640x360, 30 frames, 1 thread | **killed**; 4.2 MB anonymous memory when killed | – | 6.1 MB | 25% |

`lp_app`'s RSS stayed between 10.6 and 12.6 MB during the tests, and it was never killed.

The OOM report at the first kill showed `free:1952kB` against `min:2392kB`, 15 MB of anonymous memory (mostly `lp_app`), about 9 MB of slab, only about 250 kB of file cache and 44 kB of dirty data. Unwritten disk data was therefore not the cause; the memory was simply used up.

Every kill report showed `file-rss:0kB` for ffmpeg: its 4.4 MB of program code was being dropped from memory and read back from the card again and again. The speeds of the killed runs measure this thrashing, not ffmpeg. For example, the 123 s repack spent only 11 s of CPU in ffmpeg while the system was 99% busy.

### Memory needed (measured under qemu on the host)

| command (50 frames of the 1080p AVI) | peak RSS under qemu |
|---|---|
| `-c copy` to MP4 | 12.7 MB |
| decode only (`-f null`) | 35.9 MB |
| libx264 ultrafast, 1280x720, 1 thread | 54.8 MB |
| libx264 ultrafast, 1920x1080, 1 thread | 75.4 MB |

These include qemu's own memory, about 10 MB judging by the stream-copy run, so on the camera the 1080p encode would need about 60 MB and 720p about 40 MB (estimate). That is more than all of the camera's 34 MB, so H.264 at those sizes cannot work even with `lp_app` stopped. With `lp_app` stopped, about 19 MB would be free. That would probably be enough for a repack and maybe for a small-resolution encode; neither was tested.

### Hardware encoder for conversion

The RKVENC encoder cannot help with the existing files. It needs raw frames, and there is no hardware JPEG decoder, so each 1080p JPEG would first be decoded in software. That decode step alone was killed at 4.6 MB. Upstream ffmpeg also has no encoder for Rockchip MPP; a third-party Rockchip fork has one, but whether it works with this kernel's `mpp_vcodec` variant was not checked.

Where the encoder could help is producing H.264 directly from the sensor, as the RTSP stream does and as the SDK samples `simple_vi_venc*` show. That competes with `lp_app` for the sensor input, the encoder and RAM, so it is only realistic with `lp_app` stopped. Not tried.

## Playing the AVI from the card

lighttpd (`buddy-addons/lighttpd.md`) serves byte ranges, including behind basic auth over HTTPS: a request for the `idx1` range returned `206 Partial Content`. Fetching one 213 KB frame took 0.13–0.24 s over HTTPS. Over HTTP the earlier transfer rate was 4.7 MB/s. A browser-side player that reads `idx1` and fetches frames by range would therefore be possible, at about 4–7 fps over HTTPS and real-time 10 fps over HTTP. No such player was added.

## Recommendations

- Keep the camera producing MJPEG timelapses as it does.
- Convert on a host after mirroring the card, with ffmpeg and libx264 (or a hardware encoder on the host). Convert only finished videos: the `.avi` grows during the print, and its `idx1` index is written at the end. A `<job>.avi:D` entry in `.timelapse_videos.csv` is a likely sign that a video is finished.
- If an H.264 timelapse straight from the camera is wanted, record the RTSP stream on a host and keep one frame every N seconds.
- On the camera, any extra video work needs `lp_app` stopped (taking the camera offline) and stays limited to repacking or small resolutions.
