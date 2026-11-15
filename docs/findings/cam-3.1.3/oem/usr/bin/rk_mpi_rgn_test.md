# `rk_mpi_rgn_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_rgn_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `67628` |
| sha256 | `48595db604ffb94f907b8c4bccdd10d562be27c26a0a2f0f78dcdbd9c2672963` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`media/rockit/rockit/mpi/example`), built in Prusa's `Prusa-Cam-SOC-Linux-SDK` CI tree |
| confidence | high |

## Summary

Rockchip rkmpi unit test for the RGN (region/OSD) module. It reads a raw NV12 file, pushes it through either a VENC channel or a VPSS group, creates overlay (bitmap OSD) or cover (solid rectangle) regions on that channel, moves/shows/hides/updates them, and writes the encoded or processed output to a file. It is a developer test shipped with the SDK and not used by the camera's production software.

## Usage

Usage string printed by `argparse_usage` (verbatim): `./rk_mpi_rgn_test [-w RECT_W] [-h RECT_H]...`. The argparse descriptions are `"\nselect a test case to run."` and `"\nuse --help for details."`.

Option table reconstructed from the argparse `struct argparse_option` array built on the stack in `main` (type / short / long / help text verbatim):

| short | long | type | help (verbatim) |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-i` | `--input_raw_name` | str | input raw data file name. default(RK_NULL) |
| — | `--input_bmp_name` | str | input bmp data file name. e.g.(/userdata/mm.bmp). default(NULL) |
| `-o` | `--output_name` | str | output stream file name. default(RK_NULL). |
| `-r` | `--rgn_count` | int | the number of rgn handle. default(1). |
| `-p` | `--operation` | int | RGN operation. default(0). 0: overlay. 1: cover. 2: mosaic. |
| `-x` | `--rect_x` | int | RGN region pos x. default(0). |
| `-y` | `--rect_y` | int | RGN region pos x. default(0). *(sic; it is the y position)* |
| `-w` | `--bmp_w` | int | bmp width. default(0). \<required\> |
| `-h` | `--bmp_h` | int | bmp height. default(0). \<required\> |
| — | `--bmp_c` | int | set bitmap count. default(1). \<required\> |
| — | `--cav_c` | int | update canvas count. default(1). \<required\> |
| `-q` | `--rgn_qp` | int | rgn roi qp. default(0). |
| — | `--bAbsQp` | int | rgn Abs qp. default(0). |
| — | `--s32Qp` | int | rgn Qp number. default(0). |
| `-W` | `--raw_w` | int | raw width. default(0). \<required\> |
| `-H` | `--raw_h` | int | raw height. default(0). \<required\> |
| `-F` | `--raw_fmt` | int | raw pixel format. default(0). 0: NV12 |
| `-f` | `--format` | int | bmp pixel format. default(65552).65552: ARGB8888, 65553: ABGR8888,65554: BGRA8888,65555: RGBA8888 |
| | (no name) | int | 65548: ARGB4444, 65549: ABGR4444,65558: BGRA4444,65559: RGBA4444 |
| | (no name) | int | 65546: ARGB1555, 65547: ABGR1555,65556: RGBA5551, 65557: BGRA5551, 65561: 2BPP |
| — | `--clut_num` | int | set color loop up table num. default(0). range[0, 255]. |
| — | `--mod` | int | attach module. default(4), 4: VENC, 6: VPSS |
| `-C` | `--codec` | int | venc encode codec(8:h264, 9:mjpeg, 12:h265, 15:jpeg, ...). default(8) |
| — | `--BgAlpha` | int | BgAlpha |
| — | `--FgAlpha` | int | FgAlpha |
| — | `--LUT0` | int | set 2bpp 0 color. default(0) |
| — | `--LUT1` | int | set 2bpp 1 color default(0xffffff) |
| — | `--rgn_inv` | int | rgn invert color enable default(0) |
| — | `--inv_num` | int | rgn invert color thresh default(100) |
| — | `--inv_width` | int | rgn width of cell inverse area. default(16), 16, 32, 64 |
| — | `--inv_height` | int | rgn height of cell inverse area. default(16), 16, 32, 64 |
| `-t` | `--rgn_time` | int | test rgn number of times. default(1) |

Notes:

- The two "(no name)" rows are separate table entries with no short or long name. They only add continuation lines to the `--format` help text.
- `main` checks four context fields (stack offsets 88/92/96/100, which are `bmp_w`, `bmp_h`, `raw_w`, `raw_h`). If any of them is 0, it prints the usage and exits.
- `--operation`: the code differs from the help text. Both `unit_test_mpi_rgn_venc` and `unit_test_mpi_rgn_vpss` handle `0` → overlay and `2` → cover. Any other value, including `1`, logs `unsupport operation %d.`. `test_rgn_mosaic_process` is present in the binary but nothing calls it.
- `--mod` 4 selects the VENC path and 6 selects the VPSS path (the values are rkmpi `MOD_ID` values). Any other value exits after `RK_MPI_SYS_Exit` without running a test.

## How it works

1. `main` builds the argparse table, then calls `argparse_init`, `argparse_describe` and `argparse_parse`. It prints `cmd parse result:` followed by `rgn input raw file name   : %s` and the other parsed values.
2. It runs the required-field check, then calls `RK_MPI_SYS_Init`.
3. It dispatches on `mod` (`cmp r3,#4` → `unit_test_mpi_rgn_venc`, `cmp r3,#6` → `unit_test_mpi_rgn_vpss`) and finishes with `RK_MPI_SYS_Exit`. It logs `test running ok.` or `test running failed!`.
4. **VENC path** (`unit_test_mpi_rgn_venc`): `TEST_VENC_Start` creates a VENC channel (`RK_MPI_VENC_CreateChn`, `RK_MPI_VENC_StartRecvFrame`) and starts a send thread and a get-stream thread (`pthread_create`). The send thread reads raw frames from `input_raw_name` into an `RK_MPI_MB_CreatePool` buffer and calls `RK_MPI_VENC_SendFrame`. The get-stream thread calls `RK_MPI_VENC_GetStream` and `fwrite`s the stream to `output_name`. The region test then runs `rgn_time` times, and `TEST_VENC_Stop` tears everything down.
5. **VPSS path** (`unit_test_mpi_rgn_vpss`): `TEST_VPSS_Start` creates a VPSS group and channel (`RK_MPI_VPSS_CreateGrp/SetChnAttr/EnableChn/StartGrp`). `TEST_VPSS_StartProc` starts the threads that feed the group (`RK_MPI_VPSS_SendFrame`) and read processed frames (`RK_MPI_VPSS_GetChnFrame`, logged as `get chn[%d] frame %p length %d`). The region test runs, then `TEST_VPSS_StopProc` and `TEST_VPSS_Stop` clean up.
6. **Overlay test** (`test_rgn_overlay_process`):
   - `RK_MPI_RGN_Create` and `RK_MPI_RGN_AttachToChn` (log `The handle: %d, create success!`).
   - The bitmap comes from `input_bmp_name` (`TEST_RGN_LOAD_MEM` / `load_bmp_ex` BMP parser) or is generated (`TEST_RGN_CreateBmp`). It is applied with `RK_MPI_RGN_SetBitMap`, then with `RK_MPI_RGN_GetCanvasInfo` + `RK_MPI_RGN_UpdateCanvas`. Timing is logged (`Handle:%d, space time %lld us, update canvas success!`).
   - `TEST_RGN_ChangePosition` (`RK_MPI_RGN_SetDisplayAttr`) and `TEST_RGN_ShowOrHide`, then `RK_MPI_RGN_DetachFromChn` and `RK_MPI_RGN_Destroy`.
7. **Cover test** (`test_rgn_cover_process`): creates a cover region (`create an cover region and attach it to chn0`), resizes and moves it via `RK_MPI_RGN_GetDisplayAttr` / `RK_MPI_RGN_SetDisplayAttr` (`resize the cover region %d to <%d, %d, %d, %d>, color<0x%x>`), hides and shows it, then detaches and destroys it.
8. Common helpers linked in from the SDK `example/common` code:
   - `TEST_COMM_GetSocType` reads `/proc/device-tree/compatible`.
   - `TEST_COMM_OpenFileUris` contains http/rtsp/rtmp scheme detection strings, but only local `fopen` is used for I/O.
   - `TEST_VENC_SnapProcess` writes `/data/rgn/venc_frame%d.jpg`.

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/device-tree/compatible` (SoC detection). The rkmpi kernel devices `/dev/mpi/vsys`, `/dev/mpi/venc`, `/dev/mpi/vpss`, `/dev/mpi/vrgn`, `/dev/mpi/valloc` and `/dev/ion` are opened indirectly through `librockit.so` (paths found in librockit.so strings) [INFERENCE: which nodes are opened in practice depends on the library].
- Files and paths read/written: reads `--input_raw_name` (raw NV12) and `--input_bmp_name` (BMP). Writes `--output_name` (encoded stream or processed frames). The snapshot helper can write `/data/rgn/venc_frame%d.jpg`.
- Network: none. The URI scheme strings (`rtsp://`, `rtmp://`, `http://`, ...) belong to the shared `TEST_COMM_GetUriSchemeType` helper and are used only for classification.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. A grep of the whole `downlaods/3/dump/` tree for `rk_mpi_rgn_test` finds only the binary itself (nothing in `/etc/init.d/S??*`, `RkLunch.sh` or `/oem/usr/etc/init.d/S10ntp`). `lp_app` does not depend on it. It is a factory or developer test left in `/oem/usr/bin`.

If run manually while `lp_app` is active, it creates its own VENC channel or VPSS group and RGN handles in the same rkmpi kernel namespace. The default VENC channel 0 / VPSS group 0 and RGN handle 0 may collide with IDs used by `lp_app`, causing create failures or interference with the live stream's OSD/encoder [INFERENCE]. It does not touch flash, GPIO or LEDs. It only writes the output file the user specifies (plus possibly `/data/rgn/`).

## Evidence

```
$ readelf -d rk_mpi_rgn_test | grep NEEDED
 librockit.so libstdc++.so.6 libgcc_s.so.1 libc.so.0
$ llvm-nm-14 -D --undefined-only (RK_ imports, abbreviated)
 RK_MPI_RGN_{Create,Destroy,AttachToChn,DetachFromChn,SetBitMap,GetCanvasInfo,UpdateCanvas,GetDisplayAttr,SetDisplayAttr}
 RK_MPI_VENC_{CreateChn,DestroyChn,GetChnAttr,SendFrame,GetStream,ReleaseStream,StartRecvFrame,StopRecvFrame}
 RK_MPI_VPSS_{CreateGrp,StartGrp,StopGrp,DestroyGrp,SetChnAttr,EnableChn,DisableChn,SendFrame,GetChnFrame,...}
 RK_MPI_SYS_{Init,Exit,MmzFlushCache} RK_MPI_MB_* RK_MPI_MMZ_Alloc RK_MPI_CAL_*
$ strings -t x rk_mpi_rgn_test
 e0f0 ./rk_mpi_rgn_test [-w RECT_W] [-h RECT_H]...
 d974 RGN operation. default(0). 0: overlay. 1: cover. 2: mosaic.
 dcdc attach module. default(4), 4: VENC, 6: VPSS
 e934 /data/rgn/venc_frame%d.jpg
 e5c4 /proc/device-tree/compatible
 ede0 /home/runner/work/Prusa-Cam-SOC-Linux-SDK/Prusa-Cam-SOC-Linux-SDK/media/rockit/rockit/mpi/example/common/test_comm_bmp.cpp
main dispatch (llvm-objdump):
 13284: ldr r3,[sp,#136] ; cmp r3,#4 ; beq -> bl unit_test_mpi_rgn_venc
 13290: cmp r3,#6 ; bl 0x1473c <unit_test_mpi_rgn_vpss>
unit_test_mpi_rgn_venc operation switch:
 14684: ldr r3,[r4,#12]; cmp r3,#0 -> test_rgn_overlay_process ; cmp r3,#2 -> test_rgn_cover_process ; else RK_LOG "unsupport operation"
```

## Open questions

- Whether the RGN overlay can be attached to a channel owned by `lp_app` cannot be determined statically. This test always creates its own VENC/VPSS channel first.
- The exact VENC channel ID and resolution used by `TEST_VENC_Start` come from the context and were not fully traced. The default is assumed to be channel 0 at `raw_w`×`raw_h` [INFERENCE].
- The mosaic code (`test_rgn_mosaic_process`) is present but unreachable in this build.
