# `rk_mpi_vi_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_vi_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `55128` |
| sha256 | `c6b4180f8c0bd3b2d71eab806b501d105a58e3d12b1edf18d8947636450b530e` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`rk_mpi_vi_test`, `mpi/example`) |
| confidence | high (option table, module list); medium (mode-to-function mapping for modes 3–12) |

## Summary

Rockchip rkmpi unit test for the video-input (VI, camera/ISP capture) module. It configures and enables a VI device, pipe and channel, then, depending on `--mode`, does one of the following:

- grabs and releases raw frames, optionally saving them to `/data`
- binds VI to one or two VENC encoders and saves the bitstream
- sends VI frames to VENC manually
- runs multiple VI devices
- changes the capture resolution on the fly
- tests JPEG thumbnails, RGN overlays/covers/mosaics or IVS motion detection

On this camera it is the most direct way to capture from the sensor without `lp_app`.

## Usage

The binary contains example invocations rather than a single usage string (verbatim):

```
	1)./rk_mpi_vi_test -w 1920 -h 1080 -t 4 -c 0 -d 0 -m 0 -l 10 -o 1
	10)./rk_mpi_vi_test -w 1920 -h 1080 --width_max 2560 --height_max 1440 -c 0 -m 0
```

(`--width_max`/`--height_max` do not exist in the option table; the real names are `--maxWidth`/`--maxHeight`.) Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim; `\n\t` shown as line breaks):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-w` | `--width` | int | set capture channel width(required, default 0) |
| `-h` | `--height` | int | set capture channel height(required, default 0) |
| `-d` | `--dev` | int | set dev id(default 0) |
| `-p` | `--pipe` | int | set pipe id(default 0) |
| `-c` | `--channel` | int | set channel id(default 1) |
| `-l` | `--loopcount` | int | set capture frame count(default 100) |
| `-C` | `--compressmode` | int | set capture compressmode(default 0; 0:MODE_NONE 1:AFBC_16x16) |
| `-o` | `--output` | int | save output file, file at /data/test_\<devid\>\_\<pipeid\>\_\<channelid\>.bin (default 0; 0:no save 1:save) |
| `-m` | `--mode` | int | test mode(default 1; 0:vi get&release frame / 1:vi bind one venc(h264) / 2:vi bind two venc(h264)) / 3:vi bind vpss bind venc / 4:vi bind vo / 5:mult vi / 6:vi get send to venc / 7:vi get send to vo / 8:vi bind vpss bind vo |
| `-t` | `--memorytype` | int | set the buf memorytype(required, default 4; 1:mmap(hdmiin/bt1120/sensor input) 2:userptr(invalid) 3:overlay(invalid) 4:dma(sensor)) |
| `-n` | `--name` | str | set the entityName (required, default null; rv1126 sensor:rkispp_m_bypass rkispp_scale0 rkispp_scale1 rkispp_scale2; rv1126 hdmiin/bt1120/sensor:/dev/videox such as /dev/video19 /dev/video20; rk356x hdmiin/bt1120/sensor:/dev/videox such as /dev/video0 /dev/video1 |
| `-D` | `--depth` | int | channel output depth, default{u32BufCount(not bind) or 0(bind venc/vpss/...)} |
| `-f` | `--format` | int | set the format(default 0; 0:RK_FMT_YUV420SP 10:RK_FMT_YUV422_UYVY131080:RK_FMT_RGB_BAYER_SBGGR_12BPP) |
| — | `--codec` | int | venc encode codec(8:h264, 9:mjpeg, 12:h265, 15:jpeg, ...). default(12) |
| — | `--freeze` | int | freeze output(default 0; 0:disable freeze 1:enable freeze) |
| — | `--src_rate` | int | src frame rate(default -1; -1:not control; other:1-max_fps\<isp_out_fps\>) |
| — | `--dst_rate` | int | dst frame rate(default -1; -1:not control; other:1-src_fps\<src_rate\>) |
| — | `--buf_count` | int | out buf count, range[1-8] default(3) |
| — | `--venc_ch_start` | int | venc chn id start |
| — | `--wrap` | int | wrap enable(0: disable, 1: enable). default(0) |
| — | `--wrap_line` | int | set wrap line, range [128-H] |
| — | `--rgn_type` | int | rgn type. 0:overlay, 1:overlayEx,2:cover,3:coverEx,4:mosaic,5:moscaiEx |
| — | `--rgn_cnt` | int | rgn count. default(1),max:8 |
| — | `--en_rgn` | int | enable rgn. default(0) |
| — | `--en_overlay` | int | enable overlay. default(0) |
| — | `--mirror` | int | picture mirror, default(0) |
| — | `--flip` | int | picture flip, default(0) |
| — | `--maxWidth` | int | config max resolution width(\<= sensor max resolution width) |
| — | `--maxHeight` | int | config max resolution height(\<= sensor max resolution height) |
| — | `--combo` | int | combo enable(0: disable, 1: enable). default(0) |
| — | `--snap` | int | snap jpeg num(-1: save all, \> 0: save pic num). default(1) |
| — | `--venc_ref_buf_share` | int | enable venc ref buf share or not, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--de_breath` | int | debreath[0, 35] default(0) |
| `-b` | `--bit_rate` | int | bit rate kbps(h264/h265:range[3-200000],jpeg/mjpeg:range[5-800000] default(10*1024kb)) |
| — | `--bit_rate_max` | int | bit rate kbps max(vbr/avbr valid)(...default(0:auto calcu)) |
| — | `--bit_rate_min` | int | bit rate kbps min(vbr/avbr valid)(...default(0:auto calcu)) |
| — | `--attach_pool` | int | enable attach usr pool, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--ivs` | int | ivs(MD, OD) enable, default(0: disable, 1: low, 2: mid, 3: high) |
| — | `--no_use_v4l2` | int | enable use v4l2, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--delay_get` | int | delay some ms get, default(0) |
| — | `--svc` | int | svc(smart video coding) enable, default(0) |
| — | `--gop_size` | int | gop size(range \>= 1 default(60)) |
| — | `--change_res` | int | change res by frames(default(20)) |
| — | `--getstream` | int | ebable get vi stream,default(1) |

**Modes actually implemented.** `main` does `ldr r3,[r4,#920]; cmp r3,#12; ldrls pc,[pc,r3,lsl#2]`, a jump table with 13 entries (modes 0–12). Anything above 12 logs `no support such test mode:%d`. Each handler was attributed from the APIs and strings in its code range:

| mode | target | behaviour (from calls/strings in that block) |
|---|---|---|
| 0 | 0x13ae4 | get & release frame loop (`test_vi_get_release_frame_loop`): `signal`, `RK_MPI_VI_SetChnFreeze`, `RK_MPI_VI_GetChnFrame`, `RK_MPI_VI_QueryChnStatus`, `RK_MPI_VI_ReleaseChnFrame`. Writes frames to `/data/test_<dev>_<pipe>_<chn>.bin` when `-o 1` |
| 1, 2 | 0x13cc0 | VI bound to 1 (or 2) VENC channels (`RK_MPI_SYS_Bind`), stream read loop (`RK_MPI_VENC_GetStream`), optional IVS (`bind vi to ivs failed`, `RK_MPI_IVS_GetResults`, `MD u32RectNum: %u`). Bitstream written to `/data/venc_<n>.bin` |
| 3 | 0x13428 | "vi bind vpss bind venc": the code binds VI→VENC (`RK_MPI_SYS_Bind`, `create %d ch venc failed`). There are no VPSS imports in this binary, so the VPSS stage is compiled out [INFERENCE] |
| 4 | 0x13610 | "vi bind vo": loop printing `loopCount:%d`, then unbind/disable. No VO imports, so effectively a no-op [INFERENCE] |
| 5 | 0x136e4 | multi-VI (`test_vi_muti_vi_loop`): `RK_MPI_VI_GetDevAttr/EnableDev/SetDevBindPipe/SetChnAttr/EnableChn` per device, `dev %d GetChnFrame Success!` |
| 6 | 0x139e8 | VI get → `RK_MPI_VENC_SendFrame` → `RK_MPI_VENC_GetStream` (`test_vi_venc_get_send_loop`) |
| 7 | 0x1435c | VI get → "VO" (`RK_MPI_VO_SendFrame mpi_buf id:%d` is only logged, no VO import), plus `RK_MPI_VI_ChnSaveFile` |
| 8 | 0x13cd0 | "vi bind vpss bind vo": loop + unbind only (no VPSS/VO imports) [INFERENCE] |
| 9 | 0x13dec | "vi bind vpss send vo": logs `%d RK_MPI_VPSS_GetChnFrame failed %d with 0x%x` (stub) [INFERENCE] |
| 10 | 0x13eac | change resolution (`test_vi_change_resolution`): cycles through the built-in list `1920x1080, 1280x1080, 720 x 576, 640 x 480, 640 x 360, 512 x 288, 480 x 320, 320 x 240, 2304x1296, 2560x1440, 2880x1616` every `change_res` frames via `RK_MPI_VI_SetChnAttr` and saves `resolution_%d_%d_%d.bin` |
| 11 | 0x140e4 | VI→VENC with resolution change (`test_vi_bind_venc_change_resolution`): `RK_MPI_VENC_SetChnAttr` + `RK_MPI_VI_SetChnAttr` while bound |
| 12 | 0x13418 | VI→VENC + JPEG thumbnail: `RK_MPI_VENC_EnableThumbnail`, `RK_MPI_VENC_ThumbnailBind`, thumbnail thread, `/data/tb_%lld.jpg` |

## How it works

1. argparse; prints `test running enter ctx->aEntityName=%s!`, then `cmd parse result:` and about 35 `ctx->...` lines.
2. When `-o 1`, it builds the output name `/data` + `test_%d_%d_%d.bin` (and `vpss_%d.bin`) and opens it with `fopen("wb")`.
3. `RK_MPI_SYS_Init` (`rk mpi sys init fail!` on error), then the mode switch above.
4. VI bring-up (`create_vi` / `test_vi_init`):
   - `RK_MPI_VI_GetDevAttr`; if not already set, `RK_MPI_VI_SetDevAttr` (`RK_MPI_VI_SetDevAttr already` otherwise).
   - `RK_MPI_VI_GetDevIsEnable`; if not enabled, `RK_MPI_VI_EnableDev` and `RK_MPI_VI_SetDevBindPipe`.
   - `RK_MPI_VI_SetChnAttr`, optionally `RK_MPI_VI_SetChnWrapBufAttr` (wrap mode, `set channel wrap line: %d, wrapBuffSize = %d`) and `RK_MPI_VI_AttachMbPool` (attach_pool), then `RK_MPI_VI_EnableChn`.
   - Optional RGN on the VI channel (`create_overlay`: `RK_MPI_RGN_Create/AttachToChn/GetCanvasInfo/UpdateCanvas`, cover/mosaic attach).
5. VENC config (`init_venc_cfg(ctx, chn, codec)`): `RK_MPI_VENC_CreateChn`, `SetChnAttr`, `SetChnRefBufShareAttr`, `SetChnBufWrapAttr`, `SetComboAttr`, `SetDeBreathEffect`, `SetJpegParam`, `EnableSvc`, `StartRecvFrame`. Snapshot JPEGs go to `/data/venc_ch%d_%lld.jpg`.
6. Teardown: `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn`, `RK_MPI_VENC_StopRecvFrame/DestroyChn`, `RK_MPI_RGN_DetachFromChn/Destroy`, `RK_MPI_VI_DetachMbPool`, `RK_MPI_MB_DestroyPool`, **`RK_MPI_VI_DisableDev`**, `RK_MPI_SYS_Exit`.
7. `test_vi_poll_event(int,int)` uses `poll()` on a file descriptor (`fd > 0` assertion, `fd:%d polled error`).

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/proc/device-tree/compatible`.
  - The ISP/VI video nodes are opened through librockit (the help text mentions `/dev/videoX` entity names; librockit.so contains `/dev/video`, `/dev/media%d`, `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vrgn`, `/dev/mpi/vsys`, `/dev/ion`) [INFERENCE: exact nodes opened].
  - The ISP/sensor is reached through rkaiq/rkisp inside librockit/kernel. This test does not import `rk_aiq_*` itself.
- Files and paths read/written: `/data/test_<dev>_<pipe>_<chn>.bin`, `/data/vpss_<n>.bin`, `/data/venc_<n>.bin`, `/data/venc_ch%d_%lld.jpg`, `/data/tb_%lld.jpg`, `/data/resolution_%d_%d_%d.bin` (all under `/data`, only when output/snap is enabled).
- Network: none (URI strings only in the shared helper).
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. A grep of the whole `downlaods/3/dump/` tree for `rk_mpi_vi_test` finds only the binary. It is not referenced by `RkLunch.sh` or any init script, and `lp_app` does not use it.

If run while `lp_app` holds the camera, the test detects an already configured or enabled VI device (`RK_MPI_VI_SetDevAttr already` / `RK_MPI_VI_EnableDev already`) and proceeds to configure channel `-c` (default 1). This may collide with a channel `lp_app` uses. On exit it calls `RK_MPI_VI_DisableDev`, which could stop the live camera feed of `lp_app` [INFERENCE]. Without `lp_app` running, it is a convenient way to dump raw sensor frames or H.265 to `/data`. Writing large `.bin` files to `/data` (internal flash/userdata) consumes space. There are no GPIO, LED or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_vi_test | grep -E 'VI_|VPSS|VO_'
 RK_MPI_VI_AttachMbPool ChnSaveFile DetachMbPool DisableChn DisableDev EnableChn EnableDev GetChnFrame
 GetDevAttr GetDevIsEnable QueryChnStatus QueryDevStatus ReleaseChnFrame SetChnAttr SetChnFreeze
 SetChnWrapBufAttr SetDevAttr SetDevBindPipe       (no VPSS_* / VO_* imports)
$ main mode switch
 13360: ldr r3,[r4,#920] ; cmp r3,#12 ; ldrls pc,[pc,r3,lsl #2]
 table: 13ae4 13cc0 13cc0 13428 13610 136e4 139e8 1435c 13cd0 13dec 13eac 140e4 13418
$ strings -t x rk_mpi_vi_test
 a090 sensor probe fail
 a0bc RK_MPI_VI_SetDevAttr already
 a110 RK_MPI_VI_EnableDev already
 a344 /data/venc_ch%d_%lld.jpg
 a3d0 /data/tb_%lld.jpg
 b4f0 /data      b4f8 test_%d_%d_%d.bin     a044 venc_%d.bin    be50 resolution_%d_%d_%d.bin
 bf10 	1)./rk_mpi_vi_test -w 1920 -h 1080 -t 4 -c 0 -d 0 -m 0 -l 10 -o 1
```

## Open questions

- Which `--name` entity, dev, pipe and channel IDs match this camera's sensor (likely an rkisp mainpath/selfpath on RV1106) cannot be determined from this binary [INFERENCE].
- Modes 3/4/7/8/9 refer to VPSS/VO in their help or log text, but the binary has no VPSS/VO imports. Their behaviour is reduced to VI(+VENC) or a no-op loop [INFERENCE from imports].
- Whether `RK_MPI_VI_DisableDev` actually tears down a device owned by another process depends on librockit and the kernel MPI reference counting, which was not analysed.
