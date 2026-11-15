# `simple_venc_jpeg`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_venc_jpeg` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14348` |
| sha256 | `ce4205f86cff06f63ca383c101e9cae863f20f133c39f0e9a63bda64bce335b4` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_venc_jpeg` |
| confidence | high |

## Summary

This is an SDK demo for interactive JPEG snapshots. It binds VI → a VENC channel configured for JPEG (quality factor 77). Each line typed on stdin triggers one still capture, saved as `/tmp/test_jpeg<N>.jpeg`. Typing `quit` ends the program. It is a snapshot sample, not used by the production firmware.

## Usage

Verbatim help (printed for `?` or any unhandled option):

```
usage example:
	%s -I 0 -w 1920 -h 1080 
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
```

`getopt` string: `"?::w:h:c:I:e:"`. Options are dispatched by an if-chain that handles only:

- `-w` (default 1920);
- `-h` (default 1080);
- `-I` (VI channel, default 0).

`-c` and `-e` are accepted by `getopt` but fall into the default branch, so they **print usage and exit**. The codec is fixed to id 15 (named `JPEG` in `#CodecName`).

Interactive use after start-up:

- Press Enter (or type any line not containing `quit`) to capture one JPEG.
- Type `quit` to exit (`#Get 'quit' cmd!`). Ctrl-C also works.

## How it works

1. Defaults: frame count -1, 1920×1080, codec 15 "JPEG". Print `#CodecName`, `#Resolution`, `#CameraIdx` and `#Frame Count to save`. Install a `SIGINT` handler. Call `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr`, then `RK_MPI_VI_SetDevAttr` if needed, `RK_MPI_VI_GetDevIsEnable`, `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe`. `vi_chn_init(-I, w, h)`: `RK_MPI_VI_SetChnAttr` + `RK_MPI_VI_EnableChn`.
3. `test_venc_init(0, w, h, 15)`:
   - `RK_MPI_VENC_CreateChn(0, {codec 15, rate-control constant 7, bitrate field 10240, gop 60, profile 100, 2 buffers})`;
   - `RK_MPI_VENC_SetChnParam(0, {frame-rate control: src 25/1 → dst 10/1})` [INFERENCE: field mapping from the constant layout 0,25,1,10,1];
   - `RK_MPI_VENC_StartRecvFrame(0, …)`.
4. `RK_MPI_SYS_Bind({VI(8), 0, <-I>} → {VENC(4), 0, 0})` (`====RK_MPI_SYS_Bind vi0 to venc0====`). The program starts no rkaiq (no `rk_aiq_*` imports).
5. A thread `GetMediaBuffer0` is created. **On every loop iteration** it does `sprintf("%s/test_jpeg%d.jpeg", "/tmp/", jpeg_id)` and `fopen64(…, "w")`. Then it calls `RK_MPI_VENC_GetStream(0, …, 500 ms)`. On success it does `RK_MPI_MB_Handle2VirAddr` → `fwrite` → `fflush`, logs `chn:0, jpeg_id:%d enc->seq:%d …`, calls `RK_MPI_VENC_ReleaseStream`, and increments `jpeg_id`.
6. Main thread: `RK_MPI_VENC_SetJpegParam(0, {u32Qfactor = 77})`, then a loop of `fgets(stdin, 64)`:
   - prints `#Input cmd:%s`;
   - if the line contains `quit` (`strstr`), sets the quit flag;
   - otherwise calls `RK_MPI_VENC_StartRecvFrame(0, {s32RecvPicNum = 1})` to encode exactly one more picture (on failure prints `RK_MPI_VENC_StartRecvFrame failed!`).
7. Teardown after `sleep(1)`: `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_VI_DisableDev`, `RK_MPI_SYS_Exit`.

Observed defect: the binary imports no `fclose`, so the per-iteration `fopen64` never closes its `FILE*`. While idle, every 500 ms timeout opens (and truncates) the same `/tmp/test_jpeg<N>.jpeg` again. Over time this can exhaust file descriptors [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary. Through librockit it uses `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, rkisp `/dev/video*` and `/dev/mpp_service` [INFERENCE].
- Files and paths read/written: writes `/tmp/test_jpeg<N>.jpeg` (N = 0, 1, 2 …); `/tmp` is a tmpfs per `/etc/fstab`. Reads commands from stdin.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- It is not started at boot and is not referenced by any script or binary in the dump.
- `lp_app` does not depend on it. It shares VI dev 0 and VENC chn 0 with `lp_app`'s pipeline, so running it with `lp_app` active would likely fail or interfere [INFERENCE]. Use `/mnt/sdcard/lp_stop` to keep `lp_app` from starting.
- Without a running 3A engine (`lp_app` or `rkaiq_3A_server`) the JPEGs will be poorly exposed and uncorrected [INFERENCE].
- Side effects: it writes files only to the RAM-backed `/tmp`.

## Evidence

```
$ strings -t x simple_venc_jpeg | grep -e '?::' -e jpeg -e quit -e /tmp
   ?::w:h:c:I:e:      /tmp/      %s/test_jpeg%d.jpeg      quit
$ llvm-nm-14 -D --undefined-only simple_venc_jpeg | grep -c fclose  -> 0
```
`main`:
```
11930: mvn r3,#0 (frame cnt) ; 11938: #1920 ; 11948: mov r3,#15 ; "JPEG"
1196c: cmp opt,#'h' ; 11978: cmp opt,#'w' ; 11984: cmp opt,#'I' ; else -> usage, return
11b38: RK_MPI_SYS_Bind
11b8c: mov r3,#77 ; 11ba0: RK_MPI_VENC_SetJpegParam
11bc0: fgets(buf,64,stdin) ; 11be8: strstr(buf,"quit")
11c2c: mov r3,#1 ; 11c40: RK_MPI_VENC_StartRecvFrame
```
VENC init: `1154c mov #7`, `11554 #10240`, `1155c #60`, `11574 #100`, `115f8 RK_MPI_VENC_CreateChn`, `11604..1161c 25,1,10,1`, `11630 RK_MPI_VENC_SetChnParam`.
Thread loop head `0x11304`: `sprintf` → `fopen64("w")` → `RK_MPI_VENC_GetStream(0,…,500)` … `114d4 bne 0x11304`.

## Open questions

- The rate-control constant 7 and codec id 15 are inferred to be rockit's MJPEG/JPEG enumerators. The rockit header is not in the dump.
- The exact `VENC_CHN_PARAM_S` field mapping (25 → 10 fps) is inferred from constants, not from a header.
- Whether the first frame after start-up is captured without user input depends on the initial `StartRecvFrame` argument (memset to 0 then default). This was not determined.
