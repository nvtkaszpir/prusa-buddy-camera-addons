# `rk_mpi_vpss_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_vpss_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `55108` |
| sha256 | `96aa6cdb75cbde7a31de56073e4a1bb071c97bc16c7439149575241d7ecae1a9` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`rk_mpi_vpss_test`, `mpi/example`) |
| confidence | high |

## Summary

Rockchip rkmpi unit test for the VPSS (video process sub-system: scale, crop, rotate, mirror/flip, format conversion). It feeds frames from a raw file, or a generated pattern, into one or more VPSS groups. It configures crop, rotation and frame-rate control on the channels, reads the processed frames back, and writes them to `<output>chn_out_<W>x<H>_<grp>_<chn>.bin`. It is an SDK developer test.

## Usage

Usage string (verbatim): `./rk_mpi_vpss_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT] [-W DST_WIDTH] [-H DST_HEIGHT]...`. Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-i` | `--input` | str | input file name. e.g.(/userdata/1080p.nv12). default(NULL) |
| `-o` | `--output` | str | output file path. e.g.(/userdata/vpss/). default(NULL). |
| `-n` | `--loop_count` | int | loop running count. default(1) |
| — | `--video_proc_dev_type` | int | the device type of video process. default(0. 0 is GPU, 1 is RGA) |
| `-g` | `--group_count` | int | the count of vpss group. default(1). |
| `-c` | `--channel_count` | int | the count of vpss channel. default(1). |
| — | `--group_crop_en` | bool | vpss group crop is enabled. default(0). |
| — | `--channel_crop_en` | bool | vpss channel crop is enabled. default(0) |
| — | `--group_crop_ratio` | int | vpss group crop ratio. range(1,1000). default(1000) |
| — | `--channel_crop_ratio` | int | vpss channel crop ratio. range(1,1000). default(1000) |
| `-w` | `--src_width` | int | src width. e.g.(1920). \<required\> |
| `-h` | `--src_height` | int | src height. e.g.(1080). \<required\> |
| — | `--src_vir_width` | int | src virtual width. e.g.(1920). default(0) |
| — | `--src_vir_height` | int | src virtual height. e.g.(1080). default(0) |
| `-m` | `--src_compress` | int | src compress mode. default(0). |
| `-f` | `--src_format` | int | src pixel format. default(0. 0 is NV12). |
| `-W` | `--dst_width` | int | dst width. e.g.(1920). \<required\> |
| `-H` | `--dst_height` | int | dst height. e.g.(1080). \<required\> |
| `-M` | `--dst_compress` | int | dst compress mode. default(0). |
| `-F` | `--dst_format` | int | dst pixel format. default(0. 0 is NV12). |
| `-r` | `--rotation` | int | fixed rotation angle. default(0). 0: 0. 1: 90. 2: 180. 3: 270 |
| `-R` | `--rotation_ex` | int | any rotation angle. default(0). |
| `-a` | `--attach_mb_pool` | int | enable attach mb pool or not, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--chn_mode` | int | channel mode, default(0), 0: USER, 1: AUTO, 2: PASS-THOUGH |
| `-d` | `--chn_depth` | int | channel output depth, default(8) |
| — | `--mirror` | int | picture mirror, default(0) |
| — | `--flip` | int | picture flip, default(0) |
| — | `--src_chn_rate` | int | src vpss channel frame rate, default(-1) |
| — | `--dst_chn_rate` | int | dst vpss channel frame rate, default(-1) |
| — | `--src_grp_rate` | int | src vpss group frame rate, default(-1) |
| — | `--dst_grp_rate` | int | dst vpss group frame rate, default(-1) |

`main` requires `src_width`, `src_height`, `dst_width` and `dst_height` to be greater than 0 (four `cmp r3,#0; ble usage` checks before `RK_MPI_SYS_Init`).

## How it works

1. argparse, then `cmd parse result:` / `input  file name       : %s` / `output file name       : %s` ...
2. `RK_MPI_SYS_Init` → `TEST_VPSS_ModTest(ctx)` → `RK_MPI_SYS_Exit`. Logs `test running ok.` or `test running failed!`.
3. `TEST_VPSS_ModTest` copies the context per group and runs `TEST_VPSS_UnitTest` in one `pthread_create` thread per group (`group_count`), then `pthread_join`. On error it logs `single vpss test %d running failed.` / `Has error test.`.
4. `TEST_VPSS_ModInit`:
   - `TEST_VPSS_Start` (`RK_MPI_VPSS_CreateGrp`, `RK_MPI_VPSS_SetChnAttr`, `RK_MPI_VPSS_EnableChn`, `RK_MPI_VPSS_StartGrp`).
   - `RK_MPI_VPSS_SetVProcDev` with `video_proc_dev_type` (GPU vs RGA backend).
   - Crop via `TEST_VPSS_GrpSetZoom` / `TEST_VPSS_ChnSetZoom` (`RK_MPI_VPSS_Get/SetGrpCrop`, `Get/SetChnCrop`, scaled by the crop ratio out of 1000).
   - Rotation via `TEST_VPSS_SetChnRotation` / `SetChnRotationEx`.
   - With `attach_mb_pool`, `RK_MPI_CAL_VGS_GetPicBufferSize` + `RK_MPI_MB_CreatePool` + `RK_MPI_VPSS_AttachMbPool`.
5. `TEST_VPSS_ModSendFrame` builds a video frame (`TEST_SYS_CreateVideoFrame`), fills it from `--input` with `TEST_COMM_FileReadOneFrame` or with `TEST_COMM_FillImage`, flushes the cache and calls `RK_MPI_VPSS_SendFrame`.
6. `TEST_VPSS_ModGetChnFrame` calls `RK_MPI_VPSS_GetChnFrame`. When `--output` is set it writes with `TEST_COMM_FileWriteOneFrame` to `%schn_out_%dx%d_%d_%d.bin`, then calls `RK_MPI_VPSS_ReleaseChnFrame`. This repeats `loop_count` times.
7. Teardown: `TEST_VPSS_Stop` (`DisableChn`, `StopGrp`, `DestroyGrp`), `RK_MPI_VPSS_DetachMbPool`, `RK_MPI_MB_DestroyPool`.
8. Linked SDK helpers `TEST_SYS_VpssBindVenc`, `TEST_SYS_VdecBindVpss`, `TEST_SYS_VpssBindVo`, ... (`RK_MPI_SYS_Bind/UnBind`) are present but not reached from `main` in the traced path [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/device-tree/compatible`. Through librockit: `/dev/mpi/vpss`, `/dev/mpi/vrga`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, `/dev/ion` (strings in librockit.so) [INFERENCE: exact nodes opened].
- Files and paths read/written: reads `--input` (raw image). Writes `<--output>chn_out_<W>x<H>_<grp>_<chn>.bin`. The output path is used as a plain prefix, so it should end with `/`.
- Network: none.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. There are no references to `rk_mpi_vpss_test` anywhere in `downlaods/3/dump/` apart from the binary itself, and `lp_app` does not depend on it. It works only on file input, so it never touches the camera sensor. Running it alongside `lp_app` could fail if VPSS group 0 is already used by `lp_app`, and it competes for RGA/VPSS bandwidth [INFERENCE]. Its only side effect is writing output files.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_vpss_test | grep VPSS
 RK_MPI_VPSS_AttachMbPool CreateGrp DestroyGrp DetachMbPool DisableChn EnableChn GetChnCrop GetChnFrame
 GetChnRotation GetChnRotationEx GetGrpCrop GetGrpFrame ReleaseChnFrame ResetGrp SendFrame SetChnAttr
 SetChnCrop SetChnRotation SetChnRotationEx SetGrpCrop SetVProcDev StartGrp StopGrp
$ strings -t x rk_mpi_vpss_test
 afd8 ./rk_mpi_vpss_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT] [-W DST_WIDTH] [-H DST_HEIGHT]...
 b1b4 RK_MPI_VPSS_SetVProcDev(grp:%d) failed with %#x!
 b214 %schn_out_%dx%d_%d_%d.bin
main: bl RK_MPI_SYS_Init ; bl TEST_VPSS_ModTest ; bl RK_MPI_SYS_Exit
TEST_VPSS_ModTest: memcpy, pthread_create, pthread_join
TEST_VPSS_ModInit: TEST_VPSS_Start, RK_MPI_VPSS_SetVProcDev, TEST_VPSS_GrpSetZoom, TEST_VPSS_ChnSetZoom,
                   TEST_VPSS_SetChnRotation(Ex), RK_MPI_MB_CreatePool, RK_MPI_VPSS_AttachMbPool
```

## Open questions

- Whether `video_proc_dev_type=0` (GPU) is meaningful on RV1106, which has no GPU, is unclear. librockit probably falls back to RGA [INFERENCE].
- The exact roles of `chn_mode`, `chn_depth` and the frame-rate fields inside `TEST_VPSS_Start` were not traced instruction by instruction.
