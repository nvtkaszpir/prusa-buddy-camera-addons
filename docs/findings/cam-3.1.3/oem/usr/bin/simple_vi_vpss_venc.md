# `simple_vi_vpss_venc`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_vpss_venc` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14356` |
| sha256 | `0c01d4f036df01c2da5d5bbe506163ab19808508b4194058bc9897df3e7b3346` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_vi_vpss_venc` |
| confidence | high |

## Summary

This is an SDK demo of a three-stage pipeline: VI (camera input, default 1920×1080) → VPSS (scaler, default 1280×720) → VENC (H.264/H.265/MJPEG). The elementary stream is optionally written to a file given with `-o`. It is a pipeline sample, not used by the production firmware.

## Usage

Verbatim help (printed for `?` or any unhandled option):

```
usage example:
	%s -I 0 -W 1920 -H 1080 -w 1280 -h 720 -e h264 -o /tmp/venc.h264
	-W | --width: VI width, Default:1920
	-H | --heght: VI height, Default:1080
	-w | --disp_width: VPSS width, Default:1280
	-h | --disp_height: VPSS height, Default:720
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-e | --encode: encode type, Default:h264, Value:h264, h265, mjpeg
	-o: output path, Default:NULL
```

`getopt` string: `"?::W:H:w:h:c:I:e:o:"`. Short options only. The code defaults match the help: VI 1920×1080, VPSS/VENC 1280×720, frame count -1, cam/VI channel 0, codec h264 (id 8; `h265`→12, `mjpeg`→9, anything else prints `ERROR: Invalid encoder type.`), output NULL. `-o` is a **file path** that is opened with `fopen64(path, "w")`; if the open fails the program prints `ERROR: open file: %s fail, exit` and exits.

## How it works

1. Parse options. Print `#CodecName`, `#INPUT Resolution`, `#VPSS Resolution`, `#Output Path`, `#CameraIdx` and `#Frame Count to save`. Open the output file if `-o` was given. Install a `SIGINT` handler. Call `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr`, then `RK_MPI_VI_SetDevAttr` if needed, `RK_MPI_VI_GetDevIsEnable`, `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe`. `vi_chn_init(-I, W, H)`: `RK_MPI_VI_SetChnAttr` + `RK_MPI_VI_EnableChn`.
3. `test_vpss_init(grp 0, w, h)`: `RK_MPI_VPSS_CreateGrp(0, {max 4096×4096, frame-rate -1/-1 = no control, …})` → `RK_MPI_VPSS_SetChnAttr(0, 0, {w×h, …})` → `RK_MPI_VPSS_EnableChn` → `RK_MPI_VPSS_StartGrp`.
4. `test_venc_init(0, w, h, codec)`: `RK_MPI_VENC_CreateChn` + `RK_MPI_VENC_StartRecvFrame`.
5. Bind order:
   - `RK_MPI_SYS_Bind({VI(8), 0, <-I>} → {VPSS(6), grp 0, chn 0})`, logged as `====RK_MPI_SYS_Bind vi0 to vpss0====`;
   - `RK_MPI_SYS_Bind({VPSS(6), 0, 0} → {VENC(4), 0, 0})`, logged as `====RK_MPI_SYS_Bind vpss0 to venc0====`.
6. Thread `GetMediaBuffer0`: `RK_MPI_VENC_GetStream` → `RK_MPI_MB_Handle2VirAddr` → (if a file is open) `fwrite` + `fflush` → log `chn:0, loopCount:%d enc->seq:%d …` → `RK_MPI_VENC_ReleaseStream`. A failed get logs `RK_MPI_VENC_GetChnFrame fail %x`. After `-c` frames it sets quit and calls `fclose`.
7. Teardown: `RK_MPI_SYS_UnBind` ×2, `RK_MPI_VI_DisableChn`, `RK_MPI_VPSS_StopGrp`, `RK_MPI_VPSS_DestroyGrp`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_VI_DisableDev`, `RK_MPI_SYS_Exit`.

No rkaiq calls are made (no `rk_aiq_*` imports), so 3A must already be running elsewhere for a usable image [INFERENCE]. The output file is a raw Annex-B H.264/H.265 elementary stream or concatenated JPEG frames [INFERENCE from VENC defaults; no container code exists].

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary. Through librockit it uses `/dev/mpi/vvi`, `/dev/mpi/vpss`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, rkisp `/dev/video*`, `/dev/mpp_service` and probably `/dev/rga` for VPSS scaling [INFERENCE].
- Files and paths read/written: the `-o` file (written, mode `"w"`).
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- It is not started at boot and is not referenced by any script or binary in the dump.
- `lp_app` does not depend on it. `lp_app` imports `RK_MPI_VPSS_StopGrp`/`DestroyGrp` and the VI/VENC APIs, so it uses the same resources. Running both at once would likely fail at `CreateGrp`/`CreateChn` or disturb the production pipeline [INFERENCE].
- Side effects: it writes only the optional `-o` file (it grows without bound when `-c` is -1).

## Evidence

```
$ strings -t x simple_vi_vpss_venc | grep -e '?::' -e Bind
   ?::W:H:w:h:c:I:e:o:
   ====RK_MPI_SYS_Bind vi0 to vpss0====
   ====RK_MPI_SYS_Bind vpss0 to venc0====
$ readelf -x .data simple_vi_vpss_venc | grep 0x00023304
  0x00023304 ffffffff 3f3a3a57 ...   <- frame_cnt=-1
```
`main` defaults: `11afc mov #1920`, `#1080`, `11b0c mov #1280`, `11b14 mov #720`, `11b24 mov #8` ("H264"), output=NULL.
Sequence:
```
11e8c fopen64(out,"w") ; 11edc RK_MPI_SYS_Init ; 11f14 vi_dev_init ; 11f28 vi_chn_init
11f3c test_vpss_init(0,w,h) ; 11f50 test_venc_init(0,w,h,codec)
11f54 src={8,0,camid}  11f6c dst={6,0,0} ; 11fa0 RK_MPI_SYS_Bind
11fdc src={6,0,0} dst={4,0,0} ; 12010 RK_MPI_SYS_Bind
```
VPSS init: `11930/11938 mov #4096` (max w/h), `mvn #0` (frame rates) → `RK_MPI_VPSS_CreateGrp` → `SetChnAttr` → `EnableChn` → `StartGrp`.
Teardown calls (in order): `RK_MPI_VI_DisableChn, RK_MPI_VPSS_StopGrp, RK_MPI_VPSS_DestroyGrp, RK_MPI_VENC_StopRecvFrame, RK_MPI_VENC_DestroyChn, RK_MPI_VI_DisableDev, RK_MPI_SYS_Exit`.

## Open questions

- VPSS channel mode, compress mode and pixel-format fields were not decoded individually.
- The binary has no `RK_MPI_VPSS_DisableChn` import, so the VPSS channel is never explicitly disabled before `DestroyGrp`. Whether that matters is runtime behaviour.
- Whether VPSS scaling is done by RGA or another engine on RV1106 is decided inside librockit.
