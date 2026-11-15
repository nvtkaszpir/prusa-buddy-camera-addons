# `rkisp_demo`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rkisp_demo` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `175164` |
| sha256 | `079a936c7f27d6cb2bf95e933ad922fb892ee08b64fef1bf33ec323e0729fb33` |
| linked libraries | `librkaiq.so, librga.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0, ld-uClibc.so.1` |
| origin | Rockchip camera_engine_rkaiq `rkisp_demo` test tool |
| confidence | high |

## Summary

Rockchip's ISP capture and tuning test program. It captures frames from the rkisp V4L2 video nodes, optionally with the rkaiq 3A engine running in-process. It can dump YUV frames to files or stdout, and it offers an interactive key menu that exercises most of the `rk_aiq_uapi2_*` / `rk_aiq_user_api2_*` tuning APIs (AE, AWB, AF, DNR, sharpening, CCM, 3DLUT, dehaze, gamma, zoom, ...).

## Usage

```
Usage: %s to capture rkisp1 frames
         --width,  default 640,             optional, width of image
         --height, default 480,             optional, height of image
         --format, default NV12,            optional, fourcc of format
         --count,  default 1000,            optional, how many frames to capture
         --device,                          required, path of video device1
         --device2,                         required, path of video device2
         --stream-to,                       optional, output file path, if <file> is '-', then the data is written to stdout
         --stream-count, default 3          optional, how many frames to write files
         --stream-skip, default 30          optional, how many frames to skip befor writing file
         --vop,                             optional, drm display
         --rkaiq,                           optional, auto image quality
         --silent,                          optional, subpress debug log
         --pponeframe,                      optional, pp oneframe readback mode
         --hdr <val>,                       optional, hdr mode, val 2 means hdrx2, 3 means hdrx3 
         --sync-to-raw,                     optional, write yuv files in sync with raw
         --limit,                           optional, yuv limit range
         --ctl <val>,                       optional, sysctl procedure test 
         --iqpath <val>,                    optional, absolute path of iq file dir 
         --orp <raw_dir,w:h:raw_fmt>,       optional, absolute path of raw files dir 
         --sensor,  default os04a10,        optional, sensor names
%s: arguments --output and --device are required
```

- `--rkaiq` runs 3A in-process. `--iqpath` overrides the IQ directory (compiled-in default `/oem/etc/iqfiles`, which does not exist in this dump; the real IQ files are in `/etc/iqfiles` and `/oem/usr/share/iqfiles`).
- `--orp` feeds raw files into the ISP offline (`rk_aiq_uapi2_sysctl_prepareRkRaw`, `enqueueRkRawFile`).
- `--ctl N` loops init/deinit N times (`+++++++ TEST SYSCTL COUNTS %d`).
- `--vop` would display through DRM, but the binary does not link libdrm, so the display path is probably compiled out [INFERENCE].
- Once running, an interactive single-key menu is shown (`Usage <key>:`), e.g. `0) ABAYER2DNR: get abayer2dnr attri on sync mode.` ... `q) ... press key q or Q to quit.`

## How it works

- It parses options with `getopt_long`.
- If `--rkaiq` is given, it starts the engine: `rk_aiq_uapi2_sysctl_preInit*`, then `sysctl_init`, `sysctl_prepare` and `sysctl_start`. With multiple cameras it uses the camgroup variants instead (`rk_aiq_uapi2_camgroup_create/prepare/start`).
- It opens the V4L2 capture device (`--device`). Its fallbacks are the ISP main path `/dev/video0` and, for the RK1808/RV1126 ISPP pipeline, the pp input `/dev/video13` (`open isp mp(video0)`, `open pp input(video13)`). It then requests and queues buffers, issues STREAMON and loops on DQBUF/QBUF.
- It writes frames to `--stream-to`, or captures them to `/tmp/capture_image` / `%s/frame%d.yuv`. librga is linked for format conversion/copy.
- On exit it runs `stop aiq`, then `deinit aiq`.
- `rk_aiq_uapi2_debug_captureRawYuvSync` provides raw/yuv capture debugging.
- `srcOverlapMap.bin` suggests a multi-camera stitching test path [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/video0`, `/dev/video13`, any `--device`/`--device2` node, `/dev/media*` and the sensor subdevs through librkaiq.
- Files and paths read/written: `/oem/etc/iqfiles` (default IQ dir) or `--iqpath`; output files `--stream-to`, `/tmp/capture_image`, `%s/frame%d.yuv`; `srcOverlapMap.bin`; raw dirs given with `--orp`.
- Network: none.
- Environment variables / config files: none found in the binary.

## Relevance on this camera

It is not started at boot and nothing in the dump references it. It is a developer/debug tool left over from the SDK. If you run it while `lp_app` is streaming, it competes for the same ISP video nodes and for the 3A engine. Expect EBUSY errors or disturbed images in lp_app [INFERENCE]. It writes only to `/tmp` or user-given paths, not to flash. The interactive menu changes ISP tuning live.

## Evidence

```
$ strings -n4 rkisp_demo | grep -E 'iqfiles|/dev/video|/tmp|Usage'
/oem/etc/iqfiles
/dev/video13
/dev/video0
/tmp
/tmp/capture_image
%s/frame%d.yuv
Usage: %s to capture rkisp1 frames
imports: rk_aiq_uapi2_sysctl_{preInit,init,prepare,start,stop,deinit,updateIq,prepareRkRaw,enqueueRkRawFile},
         rk_aiq_uapi2_camgroup_*, ~100 rk_aiq_uapi2_set*/get* tuning calls, librga
$ ls etc/iqfiles  -> CAC_sc4336_OT01_40IRC_F16  CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16  jx_f37p_AXF37AA_SR2012A.json
```

## Open questions

- I did not disassemble the exact fallback logic for `--device` defaults.
- I did not confirm whether `--vop` can do anything at all without libdrm.
- The usage line says `--device` and `--device2` are both required, but the error message mentions `--output`. This is an upstream inconsistency, and I did not resolve it statically.
