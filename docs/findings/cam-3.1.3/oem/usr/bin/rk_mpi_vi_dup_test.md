# `rk_mpi_vi_dup_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_vi_dup_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `26288` |
| sha256 | `ab748d04f60e10caaa69b36922bc61b29849facf443fcf87991a067216dea7a3` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (multi-process "dup" VI test) |
| confidence | high (flow, options); medium (dup semantics) |

## Summary

rkmpi test for the "VI dup" feature: a second process opens additional channels on a VI device that is already configured and enabled by another process. On this camera that process would be `lp_app` [INFERENCE]. It never calls `RK_MPI_VI_SetDevAttr`/`EnableDev`/`SetDevBindPipe`. It only sets up and enables a VI channel, grabs frames (optionally saving them to `/data`), cycles that channel through a list of resolutions, or runs two VI channels plus an H.264 VENC channel.

## Usage

Example invocations embedded in the binary (verbatim):

```
	1)./rk_mpi_vi_dup_test -c 0 -d 0 -m 0 -l 10 -o 1
	2)./rk_mpi_vi_dup_test --width_max 2560 --height_max 1440 -c 0 -m 1 -o 1
	3)./rk_mpi_vi_dup_test -d 0 -m 2 -l 30 --buf_cnt 2
```

(`--width_max`/`--height_max` do not exist; the options are `--maxWidth`/`--maxHeight`.) Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim). The "target" column comes from the value pointer stored in each table entry:

| short | long | type | help | target |
|---|---|---|---|---|
| — | `--help` | bool | show this help message and exit | |
| | | group | basic options: | |
| `-w` | `--dev` | int | set dev id(default 0) | **width** (ctx+56, initialised to 1920) |
| `-h` | `--pipe` | int | set pipe id(default 0) | **height** (ctx+60, initialised to 1080) |
| `-d` | `--dev` | int | set dev id(default 0) | dev (ctx+0) |
| `-p` | `--pipe` | int | set pipe id(default 0) | pipe |
| `-c` | `--channel` | int | set channel id(default 1) | channel |
| `-l` | `--loopcount` | int | set capture frame count(default 100) | |
| `-o` | `--output` | int | save output file, file at /data/test_\<devid\>\_\<pipeid\>\_\<chnid\>.bin (default 0; 0:no save 1:save) | |
| `-m` | `--mode` | int | test mode(default 1; ⏎ 0:vi get&release frame ⏎ (help text ends here) | mode (ctx+800) |
| `-D` | `--depth` | int | channel output depth, default{u32BufCount(not bind) or 0(bind venc/vpss/...)} | |
| `-f` | `--format` | int | set the format(default 0; 0:RK_FMT_YUV420SP 10:RK_FMT_YUV422_UYVY131080:RK_FMT_RGB_BAYER_SBGGR_12BPP) | |
| — | `--buf_cnt` | int | out buf count, range[1-8] default(3) | |
| — | `--maxWidth` | int | config max resolution width(\<= sensor max resolution width) | |
| — | `--maxHeight` | int | config max resolution height(\<= sensor max resolution height) | |
| — | `--change_res` | int | change res by frames(default(20)) | |

The `-w`/`-h` entries are mislabelled in the source: their long names and help strings are copies of the dev/pipe entries. Because argparse matches the first long name, `--dev N` actually sets the **width** and `--pipe N` sets the **height**. Use `-d`/`-p` for the device and pipe.

Implemented modes (from `main`: `cmp r7,#1` / `#0` / `#2`; otherwise `no support such test mode:%d`):

- `0`: get and release frames on one channel, saved to `/data/test_vi_dup_<dev>_<pipe>_<chn>.bin` when `-o 1`
- `1`: resolution change, the default
- `2`: two VI channels plus a VENC, using three threads

## How it works

1. `calloc` of the context, which sets the defaults: width 1920, height 1080, mode 1 [per help], and output dir `/data` when `-o` is set. Then argparse and `cmd parse result:` / `ctx->enMode           : %d` ...
2. `RK_MPI_SYS_Init` (`rk mpi sys init fail!`).
3. **Mode 0**:
   - `vi_chn_init` (`RK_MPI_VI_SetChnAttr` + `RK_MPI_VI_EnableChn`; `ERROR: create VI  %d, error! ret=%d`).
   - Opens `/data/test_vi_dup_%d_%d_%d.bin`.
   - Loop `RK_MPI_VI_GetChnFrame` → `RK_MPI_MB_Handle2VirAddr` → `fwrite` → `RK_MPI_VI_ReleaseChnFrame`, logging `RK_MPI_VI_GetChnFrame ok:data %p loop:%d seq:%d pts:%lld ms len=%d` and `w:%d,h:%d, vw:%d,vh:%d, delay=%lldus`.
4. **Mode 1** (`vi_dup_change_resolution`): every `change_res` frames it calls `RK_MPI_VI_SetChnAttr` with the next entry of the built-in list (`1920x1080, 1280x1080, 720 x 576, 640 x 480, 640 x 360, 512 x 288, 480 x 320, 320 x 240, 2304x1296, 2560x1440, 2880x1616`, bounded by maxWidth/maxHeight). It logs `+++ Current resoIdx = %d +++` and writes one frame per resolution to `/data/reso_%d_%d_%d_%d.bin` (`res index: %d, write %s done`).
5. **Mode 2**:
   - `RK_MPI_VENC_CreateChn` (chn 1, enType 8 = H.264, max 1920×1080, gop 60), `RK_MPI_VENC_SetChnBufWrapAttr`, `RK_MPI_VENC_SetChnRefBufShareAttr`, `RK_MPI_VENC_StartRecvFrame`.
   - `vi_chn_init(1, 1280, 720, ...)` and `vi_chn_init(2, 640, 360, ...)`.
   - `RK_MPI_SYS_Bind` VI→VENC, then three `pthread_create` threads (`vi_dup_muti_vi_get_frame`, logging `chn:%d, loopCount:%d vi->seq:%d pts=%lld` / `enc->seq`) and `pthread_join`.
   - `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn` ×2, `RK_MPI_VENC_StopRecvFrame/DestroyChn`.
6. `RK_MPI_SYS_Exit`, `test running exit:0x%08x`.
7. The only VI imports are `RK_MPI_VI_SetChnAttr`, `EnableChn`, `DisableChn`, `GetChnFrame` and `ReleaseChnFrame`. There is no device-level VI call. librockit contains the matching dup implementation (`RKVIChannelDup`, `vi_create_chn_dup`, `vi_set_chn_attr_dup`, `vi chn:%d StartInDup = %d`).

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/device-tree/compatible` (shared helper). Through librockit: `/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, `/dev/video*` (strings in librockit.so) [INFERENCE].
- Files and paths read/written: `/data/test_vi_dup_<dev>_<pipe>_<chn>.bin` (mode 0) and `/data/reso_<idx>_<w>_<h>_<n>.bin` (mode 1), both only with `-o 1`.
- Network: none.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. There are no references in `downlaods/3/dump/` (init scripts, `RkLunch.sh`) other than the binary itself, and `lp_app` does not use it. It is designed to run **alongside** a primary camera process that already enabled VI device 0, so it is the intended way to grab extra frames from the live sensor while `lp_app` runs [INFERENCE].

Risks:

- Default channel 1 may already be used by `lp_app`.
- Mode 1 changes the resolution of the chosen channel.
- Mode 2 creates VENC channel 1, which may clash with `lp_app`'s encoders.

Without `lp_app` (VI device not enabled), the channel setup is expected to fail. Output files go to `/data`. There are no GPIO, LED or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_vi_dup_test | grep RK_MPI
 RK_MPI_VI_DisableChn EnableChn GetChnFrame ReleaseChnFrame SetChnAttr   (no VI_EnableDev/SetDevAttr)
 RK_MPI_VENC_CreateChn DestroyChn GetStream ReleaseStream SetChnBufWrapAttr SetChnRefBufShareAttr Start/StopRecvFrame
 RK_MPI_SYS_Init Exit Bind UnBind MmzFlushCache ; RK_MPI_MB_Handle2VirAddr ; RK_MPI_CAL_VGS_GetPicBufferSize
option table build in main:
 11b08 mov lr,#119('w') ; strb lr,[sp,#468] ; long @[sp,#472]=0x14570 "dev" ; value @[sp,#476]=r8=ctx+56
 11b10 mov r12,#104('h'); strb [sp,#500]   ; value @[sp,#508]=ctx+60
 119d0 mov r12,#1920 ; str r12,[r4,#56] ; 119e4 movw r0,#1080 ; str r0,[r4,#60]
mode dispatch: 11e28 cmp r7,#1 ; beq ; cmp r7,#0 ; beq ; cmp r7,#2 ; bne -> "no support such test mode:%d"
$ strings -t x rk_mpi_vi_dup_test
 4394 vi_dup_get_frame   43a8 vi_dup_change_resolution   4448 vi_dup_muti_vi_get_frame
 48f0 test_vi_dup_%d_%d_%d.bin   49e8 reso_%d_%d_%d_%d.bin   48b4 /data
```

## Open questions

- Whether the kernel MPI on this firmware actually allows the dup path while `lp_app` owns VI dev 0, and which VI channels `lp_app` already uses, cannot be determined statically.
- The function of the third thread in mode 2 (VENC stream reader vs. second VI reader) was inferred from log strings only.
