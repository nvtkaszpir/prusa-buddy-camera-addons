# `simple_vi_venc_rtsp`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_venc_rtsp` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `93248` |
| sha256 | `fc1f0623c0519cc18a81bab39c00e5e4aa4eb28c55d1fe107e9565f204544daa` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_vi_venc_rtsp`. It statically links the SDK's small `rtsp_demo` server (`rtsp_demo.c`, `rtsp_msg.c`) and the SDK `SAMPLE_COMM_ISP_*` helpers |
| confidence | high |

## Summary

This is a self-contained camera-to-RTSP demo. It starts the ISP 3A engine (rkaiq) and configures VI device 0. It binds VI channel 0 → VENC channel 0 (H.264 or H.265, CBR) and serves the encoded stream with an embedded RTSP server at **`rtsp://<camera-ip>:554/live/0`**. It is an SDK demo, not used by the production firmware.

## Usage

Verbatim help (printed by the function at `0x12548` for `?` or any unhandled option):

```
Usage example:
	%s -I 0 -w 1920 -h 1080 (rtsp://ip/live/0)
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-a | --aiq: iq file path, Default:/etc/iqfiles
	-c | --frame_cnt: frame number of output, Default:150
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-e | --encode: encode type, Default:h264, Value:h264, h265
	-b | --bitrate: set bitrate (Kbps), Default: 10Mbps
```

`getopt` string: `"?::a::w:h:c:I:e:b:"`. These are short options only; there is no `getopt_long`.

| opt | effect (from code) | actual default |
|---|---|---|
| `-w` / `-h` | VI channel and VENC width/height | 1920 / 1080 |
| `-a[path]` | IQ-file directory. The argument is *optional* (`a::`), so it must be attached as `-a/path`. A bare `-a` keeps the default | `/etc/iqfiles` |
| `-c` | stop after N encoded frames | **-1 (run forever)**; the help says 150 |
| `-I` | VI channel id used by `RK_MPI_VI_SetChnAttr/EnableChn/DisableChn` | 0 |
| `-e` | `h264` (codec id 8, "H264") or `h265` (id 12, "H265"). Anything else prints `ERROR: Invalid encoder type.` | h264 |
| `-b` | VENC bitrate in kbps | 10240 (`.data` `0x00002800`) |

Observed quirks:

- The ISP is always initialised for camera 0, whatever `-I` is.
- `RK_MPI_SYS_Bind` always uses VI chn 0 as the source. A non-zero `-I` therefore enables one VI channel but binds another.

## How it works

Call order in `main` (`0x125d8`):

1. Parse options. Print `#CodecName`, `#Resolution`, `#CameraIdx` and `#Frame Count to save`. Install a `SIGINT` handler.
2. **ISP:** if an IQ path is set (always true by default), print `ISP IQ file path: %s` and call `SAMPLE_COMM_ISP_Init(cam 0, hdr NORMAL, multi-sensor 0, iqdir)` and `SAMPLE_COMM_ISP_Run(0)`. These wrap `rk_aiq_uapi2_sysctl_enumStaticMetas` (to get the sensor entity name, `"ID: %d, sensor_name is %s, iqfiles is %s"`), `rk_aiq_uapi2_sysctl_init`, `rk_aiq_uapi2_sysctl_prepare` and `rk_aiq_uapi2_sysctl_start`. A cam-group path (`rk_aiq_uapi2_camgroup_*`) is also linked in but is used only for multi-sensor setups.
3. **RTSP:** `create_rtsp_demo(554)` (`0x14a18`) creates an `AF_INET`/`SOCK_STREAM` socket and binds it to `INADDR_ANY` (`htonl(0)`) port **554**, with `listen` backlog 128. It logs `rtsp server demo starting on port %d`. Then `rtsp_new_session(demo, "/live/0")` and `rtsp_set_video(session, 1=H264 | 2=H265, NULL, 0)`, followed by `rtsp_sync_video_ts(session, rtsp_get_reltime(), rtsp_get_ntptime())`.
4. `RK_MPI_SYS_Init`.
5. **VI:** `vi_dev_init`: `RK_MPI_VI_GetDevAttr(0)`. Only if the device is not yet configured: `RK_MPI_VI_SetDevAttr`, then `RK_MPI_VI_GetDevIsEnable` → `RK_MPI_VI_EnableDev(0)` → `RK_MPI_VI_SetDevBindPipe(0, pipe 0)`. `vi_chn_init(-I, w, h)`: `RK_MPI_VI_SetChnAttr(pipe 0, chn, {w, h, 2 buffers …})` → `RK_MPI_VI_EnableChn`.
6. **VENC:** `test_venc_init(chn 0, w, h, codec)`: `RK_MPI_VENC_CreateChn(0, {codec, CBR-mode constant 1, bitrate=-b, gop 60, profile 100, 2 buffers, w×h})` then `RK_MPI_VENC_StartRecvFrame(0, {-1 = unlimited})`.
7. `RK_MPI_SYS_Bind({VI(8), dev 0, chn 0} → {VENC(4), dev 0, chn 0})`, logged as `====RK_MPI_SYS_Bind vi0 to venc0====`.
8. Thread `GetMediaBuffer0` loops: `RK_MPI_VENC_GetStream(0, …)` → `RK_MPI_MB_Handle2VirAddr` → `rtsp_tx_video(session, data, len, pts)` → `rtsp_do_event(demo)` (handles client sockets) → `RK_MPI_VENC_ReleaseStream`. It logs `chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus` and stops when the loop count passes `-c`.
9. `main` sleeps in `usleep(500000)` until quit. Teardown: `rtsp_del_demo`, `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_VI_DisableDev`, `RK_MPI_SYS_Exit`, `SAMPLE_COMM_ISP_Stop(0)`.

**RTSP server implementation:** the embedded "rtsp_demo" library (source file names `rtsp_demo.c` and `rtsp_msg.c` appear in its log strings; SDP `s=rtsp_demo`).

- It supports RTP over **TCP interleaved** (`RTP/AVP/TCP`) and over **UDP** (`RTP/AVP`). UDP RTP/RTCP local port pairs are searched from 49152 to 65535.
- Video packetisers: H.264 and H.265 (`rtp_enc_h264/h265`). Audio packetisers G.711, G.726 and AAC are compiled in but unused here.
- It has no authentication; the only header handling is `CSeq`, `Session`, `Transport`, `Content-*`, `Accept`, `User-Agent` and `Server`.

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary itself. librockit uses `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, `/dev/video*` and `/dev/media%d`. librkaiq uses the ISP's V4L2 nodes [INFERENCE from library strings and `downlaods/2/find.log`].
- Files and paths read/written: reads the IQ files under `/etc/iqfiles` (via librkaiq; this camera ships `sc4336`, `sc530ai` and `jx_f37p` tuning). It writes no files.
- Network: **TCP 554 listening on all interfaces**, RTSP URL `rtsp://<ip>:554/live/0`. UDP RTP/RTCP ports 49152–65535 per client in UDP mode.
- Environment variables / config files: none read by the binary (no `getenv` import).

## Relevance on this camera

- It is not started at boot. `simple_vi_venc_rtsp` appears nowhere in `RkLunch.sh`, `/etc/init.d`, `/oem/usr/etc/init.d` or any other file in the dump.
- `lp_app` does not depend on it. `lp_app` has its own RTSP server (strings `RtspStream`, `config.rtsp_server_mode`; `downlaods/3/lp_app.sh` forces `rtsp_server_mode=2`).
- Running it alongside `lp_app` would collide on:
  - the rkaiq instance for camera 0, VI dev 0 / pipe 0 and VENC chn 0, all of which `lp_app` configures through the same kernel MPI (`/dev/mpi/*`);
  - probably TCP port 554 if `lp_app`'s RTSP server is active [INFERENCE].
- To use it as an alternative stream, create `/mnt/sdcard/lp_stop`, which `RkLunch.sh` honours to skip `lp_app`.
- It has no GPIO/PWM/flash side effects.

## Evidence

```
$ strings -t x simple_vi_venc_rtsp | grep -e '?::' -e live
  163b8 ?::a::w:h:c:I:e:b:
  ... /live/0
$ readelf -x .data simple_vi_venc_rtsp | grep 0x000363b0
  0x000363b0 ffffffff 00280000 ...    <- frame_cnt=-1, bitrate=0x2800 (10240)
```
`main` excerpt (annotated):
```
12938: bl 0x12fc4          ; SAMPLE_COMM_ISP_Init(0,0,0,iqdir)
12940: bl 0x134d0          ; SAMPLE_COMM_ISP_Run(0)
12944: movw r0,#554
12948: bl 0x14a18          ; create_rtsp_demo(554)
1296c: movt r1 -> "/live/0"
12974: bl 0x14854          ; rtsp_new_session
129ac: bl 0x14a88 (r1=1)   ; rtsp_set_video H264   (r1=2 for H265)
12a2c: bl RK_MPI_SYS_Init
12adc: bl RK_MPI_SYS_Bind  ; after "====RK_MPI_SYS_Bind vi0 to venc0===="
```
RTSP socket setup: `13eb4 socket(2,1,0)`, `13f1c movw r3,#554`, `13f44 htonl(0)`, `13fe4 listen(fd,128)`. UDP: `15984 socket(2,2,0)`, `1596c mov r3,#49152`, `15d3c cmp r3,#65536`.
Strings: `rtsp_demo.c`, `[INFO  %s:%d:%s] rtsp server demo starting on port %d`, `s=rtsp_demo`, `RTP/AVP/TCP`, `rtp_enc_h264 ret = %d`.

## Open questions

- The exact meaning of the VENC rate-control constant 1 is unconfirmed [INFERENCE: `VENC_RC_MODE_H264CBR`]. The same value is used when H.265 is selected.
- It is not verified whether `lp_app`'s RTSP server uses port 554, which would make the two mutually exclusive.
- `rtsp_do_event` runs only once per encoded frame inside the stream thread. RTSP request handling latency therefore depends on the frame rate. The effect on clients was not tested (static analysis only). Note: when `-c` is reached, the thread does set the global quit flag (`strb 1` to `.bss+0x2c` at `0x12188`), which `main` polls at `0x12b44`, so the program then tears down cleanly.
