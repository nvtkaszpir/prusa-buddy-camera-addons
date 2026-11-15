# `rk_mpi_venc_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_venc_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `55148` |
| sha256 | `0d6766c7dcb8eee1890caf3fe0b055ebb0ad32d7ea5b190554cd30467156e52e` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`rk_mpi_venc_test`, `mpi/example`) |
| confidence | high |

## Summary

Rockchip rkmpi unit test for the hardware video encoder (VENC). It reads raw YUV frames from a file, or generates a test pattern when no input is given. It encodes them with H.264, H.265, MJPEG or JPEG on N VENC channels and writes each channel's bitstream to `<output>/test_<chn>.bin`. Many options exercise individual VENC features: RC modes, GOP modes, ROI, QP map, SVC, motion deblur, debreath, intra refresh, super frame, frame lost, user data, IDR, rotation, mirror, MB-pool attach, ref-buffer share and IVS motion detection. It is an SDK developer test.

## Usage

Usage string (verbatim): `./rk_mpi_venc_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT]`. Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help text verbatim):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-i` | `--input` | str | input file name. |
| `-o` | `--output` | str | the directory of encoder output |
| `-n` | `--loop_count` | int | loop running count. default(1) |
| `-w` | `--width` | int | input source width. \<required\> |
| `-h` | `--height` | int | input source height. \<required\> |
| — | `--vir_width` | int | input source virWidth. |
| — | `--vir_height` | int | input source virHeight. |
| `-f` | `--pixel_format` | int | input source pixel format. default(0: NV12). |
| `-C` | `--codec` | int | venc encode codec(8:h264, 9:mjpeg, 12:h265, 15:jpeg, ...). default(8) |
| `-c` | `--channel_count` | int | venc channel count. default(1). |
| — | `--channel_index` | int | venc channel index. default(0). |
| — | `--channel_start` | int | venc channel start. default(0). |
| — | `--enc_buf_cnt` | int | venc encode output buffer count, default(8) |
| — | `--src_pic_size` | int | the size of input single picture |
| — | `--out_stream_size` | int | the size of out stream buff alloc, default(equal to u32BufferSize) |
| — | `--crop` | int | crop type(0:none 1:crop_only 2:crop_scale) default(0) |
| — | `--framerate` | int | framerate enable flag(0:disable 1:enable) default(0) |
| `-g` | `--gop_mode` | int | gop mode(0/1:NORMALP 2:TSVC2 3:TSVC3 4:TSVC4 5:SMARTP) default(0) |
| `-s` | `--snap_pic_cnt` | int | snap picture count(effective range[-1,0)(0, 2147483647)-1:not limit else:snap count) default(-1) |
| — | `--insert_user_data` | int | insert user data flag(0:disable 1:enable) default(0) |
| — | `--rotation` | int | rotation output(0:0 1:90 2:180 3:270) default(0) |
| — | `--compress_mode` | int | set input compressmode(default 0; 0:MODE_NONE 1:AFBC_16x16) |
| — | `--rc_mode` | int | rc mode(0:NULL 1:H264CBR 2:H264VBR 3:H264AVBR 4:H264FIXQP5:MJPEGCBR 6:MJPEGVBR 7:MJPEGFIXQP8:H265CBR 9:H265VBR 10:H265AVBR 11:H265FIXQP default(1) |
| `-b` | `--bit_rate` | int | bit rate kbps(h264/h265:range[3-200000],jpeg/mjpeg:range[5-800000] default(10*1024kb)) |
| — | `--bit_rate_max` | int | bit rate kbps max(vbr/avbr valid)(h264/h265:range[3-200000];jpeg/mjpeg:range[5-800000] default(0:auto calcu)) |
| — | `--bit_rate_min` | int | bit rate kbps min(vbr/avbr valid)(h264/h265:range[3-200000];jpeg/mjpeg:range[5-800000] default(0:auto calcu)) |
| — | `--gop_size` | int | gop size(range >= 1 default(60)) |
| — | `--mirror` | int | enMirror output(0:none 1:horizontal 2:vertical) default(0) |
| — | `--super_frm` | int | super frm enable(0:disable 1:enable) default(0) |
| — | `--frm_lost` | int | frm lost enable(0:disable 1:enable) default(0) |
| — | `--intra_refresh` | int | intra refresh enable(0:disable 1:enable) default(0) |
| — | `--hier_qp` | int | hierarchical qp enable(0:disable 1:enable) default(0) |
| — | `--mjpeg_param` | int | mjpeg param enable(0:disable 1:enable) default(0) |
| — | `--mjpeg_rc_param` | int | mjpeg rc param test enable(0:disable 1:enable) default(0) |
| — | `--force_idr` | int | force idr enable(0:disable 1:enable) default(0) |
| — | `--roi_count` | int | roi test count(range[0-8] default(0)) |
| — | `--fix_qp` | int | set fix qp(this value valid when rc_mode is fixqp;default(0)) |
| — | `--full_range` | int | set clolor range(0:limit color range 1:full color range) default(1) |
| — | `--send_frame_ex` | int | send frame ex enable(0:disable 1:enable) default(0) |
| — | `--qpmap` | int | qpmap enable(0:disable 1:enable) default(0) |
| — | `--attach_mb_pool` | int | enable attach mb pool or not, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--de_breath` | int | debreath[0, 35] default(0) |
| — | `--venc_ref_buf_share` | int | enable venc ref buf share or not, default(0), 0: RK_FALSE, 1: RK_TRUE |
| — | `--ivs` | int | ivs(MD, OD) enable, default(0) |
| — | `--stat_time` | int | rc statistic time(range[1,60]) default(3) |
| — | `--svc` | int | svc(smart video coding) enable, default(0) |
| — | `--motion_deblur` | int | motion deblur enable(0:disable 1:enable) default(0) |
| — | `--sao` | int | SAO(H265) enable, default(0) |
| — | `--getstream` | int | get stream enable, default(1) |

Before `RK_MPI_SYS_Init`, `main` validates four context fields (one compared against a constant, three checked for non-zero; they include width and height). If validation fails it calls `argparse_usage`.

## How it works

1. Argument parsing (argparse), then the printout `cmd parse result:` / `input  file name       : %s` / `output file name       : %s` ...
2. `RK_MPI_SYS_Init` → `unit_test_mpi_venc(ctx)` → `RK_MPI_SYS_Exit`. Logs `test running success!` or `test running failed!`.
3. `unit_test_mpi_venc`, for each of `channel_count` channels starting at `channel_start`:
   - `RK_MPI_MB_CreatePool` for input frames (`create vencPoolInput failed!`). The `TEST_VENC_SET_BitRate`, `TEST_VENC_SET_FixQp` and `TEST_VENC_SET_StatTime` helpers fill the RC attributes.
   - `RK_MPI_VENC_CreateChn`, then optional feature calls driven by the options: `RK_MPI_VENC_EnableMotionDeblur`, `SetChnParam`, `SetChnRefBufShareAttr`, `SetChnAttr`, `SetRoiAttr` (roi_count), `SetMjpegParam`, `SetRcParam`, `SetFrameLostStrategy`, `SetDeBreathEffect`, `SetHierarchicalQp`, `SetIntraRefresh`, `SetSuperFrameStrategy`, `SetH264Vui`/`SetH265Vui`, `SetH265Sao`, `SetJpegParam`, `SetChnRotation`, `EnableSvc`. With `attach_mb_pool` it creates an output pool and calls `RK_MPI_VENC_AttachMbPool` (`create vencPoolOutput[%d] failed!`).
   - With `ivs` it creates an IVS channel (`RK_MPI_IVS_CreateChn`; `ivs init failed:%x`) and opens `/data/ivs_result.txt`.
   - `RK_MPI_VENC_StartRecvFrame`, then threads via `pthread_create`:
     - `venc_send_frame`: reads `src_pic_size` bytes per frame from `--input` with `fread`, or generates a pattern with `TEST_COMM_FillImage` when there is no input. It flushes the cache and calls `RK_MPI_VENC_SendFrame`, or `RK_MPI_VENC_SendFrameEx` plus `RK_MPI_VENC_SetQpmap` (`h265_set_qpmap_64x64`) when qpmap is enabled. It optionally calls `RK_MPI_VENC_InsertUserData` (`this is rockchip user data`, `rockchip continuous user data:%d`) and `RK_MPI_IVS_SendFrame`/`GetResults` (motion-detection rectangles `MD u32RectNum: %u`, written to `/data/ivs_result.txt`). At EOF it seeks back (`seek finish ch %d`) until `loop_count` is reached.
     - `venc_get_stream`: `mkdir(output)`, opens `%s/test_%d.bin`, loops `RK_MPI_VENC_GetStream` → `RK_MPI_MB_Handle2VirAddr` → `fwrite` → `RK_MPI_VENC_ReleaseStream` until EOS (`chn %d reach EOS stream`).
     - `venc_force_idr`: periodically calls `RK_MPI_VENC_RequestIDR` (force_idr).
   - Teardown: `pthread_join`, `RK_MPI_VENC_StopRecvFrame`, `RK_MPI_VENC_DetachMbPool`, `RK_MPI_VENC_DestroyChn`, `RK_MPI_MB_DestroyPool`, `RK_MPI_IVS_DestroyChn`, and `fsync`/`fclose` of the IVS file.
4. Linked-in SDK helpers include `TEST_VENC_SnapProcess` (writes `/data/rgn/venc_frame%d.jpg`) and the `TEST_COMM_*` file and SoC helpers (`/proc/device-tree/compatible`).

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/device-tree/compatible`. Indirectly via `librockit.so`: `/dev/mpi/vsys`, `/dev/mpi/venc`, `/dev/mpi/valloc`, `/dev/ion` (strings in librockit.so) [INFERENCE: exact set opened].
- Files and paths read/written:
  - reads `--input`
  - writes `<--output>/test_<chn>.bin` (creates the directory with `mkdir`)
  - `/data/ivs_result.txt` (when `--ivs`)
  - possibly `/data/rgn/venc_frame%d.jpg` (snap helper)
- Network: none. The URI-scheme strings are only in the shared helper.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. A grep of `downlaods/3/dump/` for the name finds only the binary (no init script, `RkLunch.sh` or S-script reference). `lp_app` does not use it. Running it manually while `lp_app` streams creates additional VENC channels starting at `channel_start` (default 0). These can collide with channel IDs `lp_app` already owns (the create would fail) and share the single encoder's time and memory with the live stream [INFERENCE]. It writes only to the paths listed above. It has no flash, GPIO or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_venc_test | grep RK_MPI_VENC   (34 symbols)
 AttachMbPool CreateChn DestroyChn DetachMbPool EnableMotionDeblur EnableSvc GetChnAttr GetH264Vui GetH265Vui
 GetStream InsertUserData ReleaseStream RequestIDR SendFrame SendFrameEx SetChnAttr SetChnParam
 SetChnRefBufShareAttr SetChnRotation SetDeBreathEffect SetFrameLostStrategy SetH264Vui SetH265Sao SetH265Vui
 SetHierarchicalQp SetIntraRefresh SetJpegParam SetMjpegParam SetQpmap SetRcParam SetRoiAttr
 SetSuperFrameStrategy StartRecvFrame StopRecvFrame
 + RK_MPI_IVS_{CreateChn,DestroyChn,SendFrame,GetResults,ReleaseResults}
$ strings -t x rk_mpi_venc_test
 a8cc %s/test_%d.bin
 aae0 /data/ivs_result.txt
 bd30 ./rk_mpi_venc_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT]
internal functions (dynsym): main, venc_force_idr(void*), venc_get_stream(void*), venc_send_frame(void*),
 h265_set_qpmap_64x64, unit_test_mpi_venc(_rkMpiVENCCtx*)
main: ... bl RK_MPI_SYS_Init ; bl unit_test_mpi_vencP13_rkMpiVENCCtx ; bl RK_MPI_SYS_Exit
```

## Open questions

- The exact per-option code paths inside the large `unit_test_mpi_venc` (about 24 KB) were only traced at the level of which API is called. Option-to-API mapping is inferred from names [INFERENCE].
- Whether VENC channel IDs used by this test overlap with those used by `lp_app` cannot be checked statically, because `lp_app` is not in this directory.
