# `simple_venc_osd`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_venc_osd` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14348` |
| sha256 | `a6198474a7b7bbdc1d9c8f2960164f8031a0842c86c1c65029bfe6ec90577857` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_venc_osd` |
| confidence | high |

## Summary

This is an SDK demo for an OSD (on-screen display) overlay. It binds VI → VENC (H.264/H.265/MJPEG). It creates one 128×128 ARGB overlay region with the RGN module and attaches it to the encoder channel at position (100,100). The overlay bitmap is loaded from the raw file `/data/res/rgn/44`; if that file is missing, the overlay is filled with solid colour bands. The encoded stream is optionally written to a file. It is not used by the production firmware.

## Usage

Verbatim help (printed for `?` or any unhandled option):

```
usage example:
	%s -I 0 -w 1920 -h 1080 -o /tmp/venc.h264
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-e | --encode: encode type, Default:h264, Value:h264, h265, mjpeg
	-o: output path, Default:NULL
```

`getopt` string: `"?::w:h:c:I:e:o:"`. Short options only. The code defaults match the help: 1920×1080, frame count -1, VI channel 0, codec h264 (id 8; `h265`→12, `mjpeg`→9, anything else prints `ERROR: Invalid encoder type.`), output NULL. `-o <file>` is opened with `fopen64(path, "w")`; if the open fails the program prints `ERROR: open file: %s fail, exit`. The overlay file path is hard-coded and cannot be changed.

## How it works

1. Parse options. Print `#CodecName`, `#Resolution`, `#Output Path`, `#CameraIdx` and `#Frame Count to save`. Open the output file if `-o` was given. Install a `SIGINT` handler. Call `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr`, then `RK_MPI_VI_SetDevAttr` if needed, `RK_MPI_VI_GetDevIsEnable`, `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe`. `vi_chn_init(-I, w, h)`: `RK_MPI_VI_SetChnAttr` + `RK_MPI_VI_EnableChn`.
3. `test_venc_init(0, w, h, codec)`: `RK_MPI_VENC_CreateChn(0, {codec, rate-control constant 1, 10240 kbps, gop 60, …})` + `RK_MPI_VENC_StartRecvFrame`.
4. `RK_MPI_SYS_Bind({VI(8), 0, <-I>} → {VENC(4), 0, 0})` (`====RK_MPI_SYS_Bind vi0 to venc0====`).
5. `test_rgn_overlay_process()`:
   - `RK_MPI_RGN_Create(handle 0, {type 0 = OVERLAY, pixel format 0x10010, 128×128})`. On failure it logs and calls `RK_MPI_RGN_Destroy`.
   - `RK_MPI_RGN_AttachToChn(0, {VENC(4), dev 0, chn 0}, {bShow = 1, OVERLAY, point (100,100), …})` (`Display region to chn success!`).
   - It allocates a bitmap of 128·128·4 bytes and calls `load_file_osdmem("/data/res/rgn/44", buf, 128, 128, 4, 0)`, which does `fopen64(…,"rb")` and `fread`. If the load fails (`open filename: %s file failed!`), it fills the buffer with 32-bit colour values `0xff0000ff`, `0x00ff00ff`, `0x0000ffff` and `0x000000ff` in four bands.
   - `RK_MPI_RGN_SetBitMap(0, {fmt 0x10010, 128, 128, data})`, timed with `clock_gettime` (`Handle:%d, space time %lld us, load bmp success!`).
6. Thread `GetMediaBuffer0`: `RK_MPI_VENC_GetStream` → `RK_MPI_MB_Handle2VirAddr` → (if a file is open) `fwrite` + `fflush` → log → `RK_MPI_VENC_ReleaseStream`. It stops after `-c` frames or on Ctrl-C.
7. Teardown: `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_VI_DisableDev`, `RK_MPI_SYS_Exit`. `RK_MPI_RGN_Destroy` is called only on the create-failure path, so the region is not explicitly detached or destroyed at exit.

The program starts no rkaiq (no `rk_aiq_*` imports).

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary. Through librockit it uses `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vrgn`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, rkisp `/dev/video*` and `/dev/mpp_service` [INFERENCE].
- Files and paths read/written: reads `/data/res/rgn/44` (raw 128×128×4 bitmap). This file is not present in the dump; `downlaods/2/find.log` has no `res/rgn` entry. It writes the `-o` file if given.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- It is not started at boot and is not referenced by any script or binary in the dump.
- `lp_app` does not depend on it. It uses the same VI dev 0 / VENC chn 0 / RGN handle space as the production pipeline, so running both at once would likely fail or put a test overlay on `lp_app`'s encoder channel 0 [INFERENCE]. Use `/mnt/sdcard/lp_stop` to keep `lp_app` from starting.
- Side effects: it writes only the optional `-o` file.

## Evidence

```
$ strings -t x simple_venc_osd | grep -e '?::' -e rgn -e osdmem
   3304 ?::w:h:c:I:e:o:
   ... /data/res/rgn/44   load_file_osdmem   test_rgn_overlay_process
$ llvm-nm-14 -D --undefined-only simple_venc_osd | grep RGN
   RK_MPI_RGN_AttachToChn RK_MPI_RGN_Create RK_MPI_RGN_Destroy RK_MPI_RGN_SetBitMap
```
`test_rgn_overlay_process` (`0x116c8`):
```
11710/11718: mov #128 (w,h)   11720/11728: mov #100 (x,y)   11734: "/data/res/rgn/44"
1173c: mov r3,#4 -> stMppChn.enModId = VENC
1175c: mov r3,#16 ; movt r3,#1 -> pixel format 0x10010
11790: RK_MPI_RGN_Create ; 117dc: RK_MPI_RGN_Destroy (error path only)
11830: bShow=1 ; 11840/11848: point = (100,100) ; 118e0: RK_MPI_RGN_AttachToChn
119f0: load_file_osdmem(path,buf,128,128,4,0) ; 11a00: beq -> SetBitMap (success)
11a14/11a40/11a6c/11aa0: colours 0xff0000ff, 0x00ff00ff, 0x0000ffff, 0x000000ff
11ab4: RK_MPI_RGN_SetBitMap
```
`main`: `12380 RK_MPI_SYS_Bind` then `123bc bl 0x116c8` (overlay) then `123d4 pthread_create`.

## Open questions

- The exact name of rockit pixel format `0x10010` is not confirmed [INFERENCE: ARGB8888, consistent with 4 bytes per pixel].
- The fallback fill uses byte offsets of `pixels`, `2·pixels` and `3·pixels` with 32-bit stores, so the bands overlap and only partly cover the buffer. The resulting image was not reproduced.
- The origin and format of `/data/res/rgn/44` in the SDK is unknown. The file does not exist on this camera.
