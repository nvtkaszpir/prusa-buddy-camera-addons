# `simple_vi_venc_change_resolution`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_venc_change_resolution` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14420` |
| sha256 | `331d058919af7eae11c8b5b4f52e3dd8c79cec7a284389b82c0a81d73a0632c1` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_vi_venc_change_resolution` |
| confidence | high |

## Summary

This is an SDK demo for changing resolution at run time. It binds VI → VENC (H.264, H.265 or MJPEG). Every 100 encoded frames it unbinds and switches both the encoder and the VI channel to the next resolution in a built-in table, then rebinds. The encoded data is fetched and **discarded**: it writes no file and has no network output. It is a stress/feature test of dynamic resolution switching, not used by the production firmware.

## Usage

Verbatim help (printed for `?` or any unhandled option):

```
usage example:
	%s -I 0 -w 1920 -h 1080 -o /tmp/venc.h264
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:150
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-e | --encode: encode type, Default:h264, Value:h264, h265, mjpeg
```

`getopt` string: `"?::w:h:c:I:e:"`.

- `-o` is **not** accepted, despite the usage example. It hits the default case, prints usage and exits. The binary imports no `fopen`/`fwrite`.
- `-w`/`-h`: initial VI/VENC size (default 1920×1080).
- `-c`: stop after N frames. The actual default is **-1 (forever)**, not 150.
- `-I`: VI channel id (default 0).
- `-e`: `h264`→codec id 8 ("H264"), `h265`→12 ("H265"), `mjpeg`→9 ("MJPEG"). Anything else prints `ERROR: Invalid encoder type.` The default is h264.

## How it works

1. Parse options. Print `#CodecName`, `#Resolution`, `#CameraIdx` and `#Frame Count to save`. Install a `SIGINT` handler. Call `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr`, then `RK_MPI_VI_SetDevAttr` if needed, `RK_MPI_VI_GetDevIsEnable`, `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe`. `vi_chn_init(-I, w, h)`: `RK_MPI_VI_SetChnAttr` + `RK_MPI_VI_EnableChn`.
3. `test_venc_init(0, w, h, codec)`: `RK_MPI_VENC_CreateChn` with
   - rate-control constant 1, bitrate 10240 kbps, gop 60, profile 100;
   - **max size 2304×1296** and stream buffer `0x445800` bytes (= 2304×1296×1.5);
   - then `RK_MPI_VENC_StartRecvFrame`.
4. `RK_MPI_SYS_Bind(VI dev 0 chn <-I> → VENC chn 0)` (`====RK_MPI_SYS_Bind vi0 to venc0====`). The program does **not** start rkaiq; it imports no `rk_aiq_*` symbols.
5. Thread `GetMediaBuffer0`: `RK_MPI_VENC_GetStream` → log `chn:0, loopCount:%d enc->seq:%d …` → `RK_MPI_VENC_ReleaseStream`. The stream data is not stored. Each time `loopCount % 100 == 0` it:
   - prints `===change resolution===`;
   - wraps the table index at 9;
   - calls `RK_MPI_SYS_UnBind` (VI chn 0 → VENC 0);
   - calls `RK_MPI_VENC_SetChnAttr(0, {w,h from table, max 2304×1296})`;
   - calls `RK_MPI_VI_SetChnAttr(0, 0, {w,h})`, logging `====RK_MPI_VI_SetChnAttr %d x %d success====` or `… fail, ret: %x`;
   - calls `RK_MPI_SYS_Bind` again and increments the index.
6. Resolution table (`.data+0x234`, entries of {width, height, label}):

   | idx | width×height (used) | label string |
   |---|---|---|
   | 0 | 1920×1080 | `1920x1080` |
   | 1 | 1280×720 | `1280x1080` (label typo) |
   | 2 | 720×576 | `720 x 576` |
   | 3 | 640×480 | `640 x 480` |
   | 4 | 640×360 | `640 x 360` |
   | 5 | 512×288 | `512 x 288` |
   | 6 | 480×320 | `480 x 320` |
   | 7 | 320×240 | `320 x 240` |
   | 8 | 2304×1296 | `2304x1296` |

7. Exit happens on Ctrl-C or once `loopCount > -c`. Teardown: `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_VI_DisableDev`, `RK_MPI_SYS_Exit`.

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary. Through librockit it uses `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, rkisp `/dev/video*` and `/dev/mpp_service` [INFERENCE from library strings].
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- It is not started at boot and is not referenced by any script or binary in the dump.
- `lp_app` does not depend on it.
- It does not run the 3A engine, so it needs one already running to get a properly exposed image: `lp_app`, `rkaiq_3A_server` (present in `/oem/usr/bin`) or another `SAMPLE_COMM_ISP` user [INFERENCE]. However, while `lp_app` owns VI dev 0 / VENC chn 0, the `CreateChn`/`SetChnAttr` calls would likely fail or disturb the production stream [INFERENCE]. Use `/mnt/sdcard/lp_stop` to keep `lp_app` from starting.
- There are no persistent side effects.

## Evidence

```
$ strings -t x simple_vi_venc_change_resolution | grep -e '?::' -e 'change resolution'
   334c ?::w:h:c:I:e:
   ... ===change resolution===
$ readelf -x .data simple_vi_venc_change_resolution
  0x000232dc ffffffff 80070000 38040000 88220100   <- frame_cnt=-1; {1920,1080,"1920x1080"}
  0x000232ec 00050000 d0020000 94220100 d0020000   <- {1280,720,"1280x1080"}, {720,...
  0x0002333c dc220100 00090000 10050000 e8220100   <- {2304,1296,"2304x1296"}
```
Jump table for `opt-'I'`: `I`, `c`, `e`, `h` and `w` only.
Thread:
```
11100: mov r3,#9            ; table entries
1123c: smull ... #0x51eb851f ; mov r1,#100 -> loopCount % 100
11264: puts("===change resolution===")
11294: RK_MPI_SYS_UnBind
11378: RK_MPI_VENC_SetChnAttr
113f0: RK_MPI_VI_SetChnAttr
114f0: RK_MPI_SYS_Bind
```
VENC init: `11610 mov r3,#10240`, `11618 #60`, `11630 #100`, `11638 #2304`, `11640 #1296`, `11670/11674 0x445800`, `11688 RK_MPI_VENC_CreateChn`.
`llvm-nm-14 -D --undefined-only` shows no `rk_aiq_*`, `fopen*`, `socket`.

## Open questions

- The resolution switch rebinds from VI chn 0 regardless of `-I`. With `-I` ≠ 0 the rebind would use a different channel than the initial bind. This is a sample bug and was not tested.
- Switching VI channel attributes on an enabled channel without disabling it may not be supported for every size. The success of each step can only be seen at run time.
- The rate-control constant 1 is unconfirmed [INFERENCE: CBR].
