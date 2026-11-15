# `rk_mpi_dup_venc_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_dup_venc_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `42740` |
| sha256 | `8d1095f48e19e4a131ff83b0e5e97ae10da4d1354cef0ecf08f383d32b8c7f43` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (rkmpi multi-process "dup" VENC test) |
| confidence | high (flow); medium (cross-process semantics) |

## Summary

rkmpi test that attaches to an **already existing** VENC channel, normally one created by another process. It does not create a channel. It prints the channel's encoder, rate-control, parameter and ROI attributes, writes them back, and forces the bitrate to 1024 kbps. It can insert SEI user data, and it reads the encoded bitstream into `<output>/test_<chn>.bin`. On this camera that makes it a tool to tap or inspect the H.264/H.265 stream that `lp_app` is encoding [INFERENCE: depends on rockit multi-process ("dup") support].

## Usage

Usage string (verbatim, copied from the VENC test): `./rk_mpi_venc_test [-o OUTPUT_PATH]`. Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-o` | `--output` | str | the directory of encoder output |
| — | `--channel_index` | int | venc channel index. default(0). |
| — | `--insert_user_data` | int | insert user data flag(0:disable 1:enable) default(0) |

## How it works

1. argparse, then `cmd parse result:` / `output file name       : %s` / `channel index          : %d`.
2. `RK_MPI_SYS_Init` → `venc_get_stream(ctx)` (called directly, not in a thread) → `RK_MPI_SYS_Exit` → `test running success!`. **No `RK_MPI_VENC_CreateChn` is called from `main`.** `TEST_VENC_Create` is linked in from the SDK common code but is not on the `main` path.
3. `venc_get_stream`, on channel `channel_index`:
   - `RK_MPI_VENC_GetChnAttr`, then prints `stVencAttr.enType`, `u32MaxPicWidth`, `u32PicWidth/Height`, `u32VirWidth/Height`, `u32StreamBufCnt`, `stRcAttr.enRcMode` and the matching CBR/VBR/AVBR/FixQp block (`.stH264Cbr.u32Gop`, `.u32BitRate`, `.u32SrcFrameRateNum`, ...) and the `stGopAttr` fields.
   - `TEST_VENC_SET_BitRate(&rc, 1024, 1024, 1024)` (`mov r3,#1024; mov r2,r3; mov r1,r3`), then **`RK_MPI_VENC_SetChnAttr`**. This changes the live channel's bitrate, max and min to 1024 kbps.
   - `RK_MPI_VENC_GetChnParam`, prints `stCropCfg` and `stFrameRate`, then `RK_MPI_VENC_SetChnParam` (written back unchanged).
   - `RK_MPI_VENC_GetRcParam`, prints `s32FirstFrameStartQp` and the codec-specific `stParamH264/H265/Mjpeg` QPs (branches on enType 8/12/9), then `RK_MPI_VENC_SetRcParam`.
   - ROI index 0–7: `RK_MPI_VENC_GetRoiAttr` → `dump_venc_roi_attr`. If the ROI is enabled, `RK_MPI_VENC_SetRoiAttr` writes it back.
   - With `insert_user_data`: `RK_MPI_VENC_InsertUserData` with the 27-byte `this is rockchip user data` and `rockchip continuous user data:%d`.
   - With `--output`: `mkdir(output, 0777)` and `fopen("%s/test_%d.bin","wb")`.
   - Loop: `RK_MPI_VENC_GetStream(chn, &stream, -1)` (blocking). If a file is open, `RK_MPI_MB_Handle2VirAddr` → `fwrite` → `fflush`. Then `RK_MPI_VENC_ReleaseStream`. Each frame is logged as `get chn %d stream %d`. On error it waits with `usleep(1000)` and retries. It exits when the pack's EOS flag is set (`chn %d reach EOS stream`) or a quit flag in the context is set.
4. `librockit.so` contains multi-process "dup" infrastructure: `opt_chan_dup`, `opt_run_in_dup`, `RKVIChannelDup`, `chn dup:    %d`. This test is the VENC counterpart [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/device-tree/compatible` (shared helper). Through librockit: `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc` (strings in librockit.so) [INFERENCE].
- Files and paths read/written: `<--output>/test_<channel_index>.bin` (created). The linked helper string `/data/rgn/venc_frame%d.jpg` is not on the `main` path.
- Network: none.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. A grep of `downlaods/3/dump/` finds only the binary itself, and it is not referenced by `RkLunch.sh`, the init scripts or `lp_app`.

It is the test most likely to interact with the running production pipeline. Its design assumes the VENC channel already exists, which on this camera means `lp_app`'s encoder.

- If rockit allows cross-process access, running it while `lp_app` streams would dump the live encoder settings and save the stream.
- It would also **reconfigure the live encoder to 1024 kbps** (`RK_MPI_VENC_SetChnAttr`) until `lp_app` resets it. With `--insert_user_data 1` it would also inject SEI user data into the stream [INFERENCE].
- If `lp_app` is not running, `RK_MPI_VENC_GetChnAttr` on a non-existent channel fails, and the test prints zeroed fields or loops on errors.

It has no flash, GPIO or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_dup_venc_test | grep VENC
 RK_MPI_VENC_CreateChn DestroyChn GetChnAttr GetChnParam GetRcParam GetRoiAttr GetStream InsertUserData
 ReleaseStream SendFrame SetChnAttr SetChnParam SetRcParam SetRoiAttr StartRecvFrame StopRecvFrame
 (CreateChn/SendFrame/... only referenced by the linked TEST_VENC_* helpers)
main (0x119c0) calls: argparse_init, argparse_describe, argparse_parse, puts, printf x2,
 RK_MPI_SYS_Init, venc_get_stream(void*), RK_MPI_SYS_Exit, RK_LOG("test running success!")
venc_get_stream:
 11d8c bl RK_MPI_VENC_GetChnAttr
 11f4c mov r3,#1024 ; mov r2,r3 ; mov r1,r3 ; bl TEST_VENC_SET_BitRate ; bl RK_MPI_VENC_SetChnAttr
 12070 bl RK_MPI_VENC_GetRcParam ... 120c8 bl RK_MPI_VENC_SetRcParam
 120ec bl RK_MPI_VENC_GetRoiAttr ; bl dump_venc_roi_attr ; (loop r5<8) ; bl RK_MPI_VENC_SetRoiAttr
 12148 "%s/test_%d.bin" ; 121a4 bl RK_MPI_VENC_GetStream (r2=-1)
$ strings -t x rk_mpi_dup_venc_test
 8f08 this is rockchip user data
 90a4 ./rk_mpi_venc_test [-o OUTPUT_PATH]
$ strings librockit.so | grep -i dup
 opt_chan_dup  opt_run_in_dup  RKVIChannelDup  vi_create_chn_dup  "	 chn dup:    %d"
```

## Open questions

- Whether rockit on this firmware lets a second process open another process's VENC channel, and which channel index `lp_app` uses, cannot be determined statically [INFERENCE].
- The location of the context "quit" flag at offset +8 was not traced. The test appears to run until an EOS frame or until it is killed.
