# `rk_mpi_tde_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_tde_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `26220` |
| sha256 | `dec3550aaae632ea1d8b32b9c0cd591b1be09a871eb5d926828fc03d09ec1add` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`rk_mpi_tde_test`, `mpi/example`) |
| confidence | high |

## Summary

Rockchip rkmpi unit test for the TDE (2-D graphics engine) API, which is backed by RGA on Rockchip [INFERENCE]. It loads a raw source image from a file into MMZ memory. It then runs jobs of quick-copy, resize, fill, rotate, mirror/flip or colour-key blit tasks with `RK_TDE_*` and saves the destination surfaces to files. It is an SDK developer test with no camera involvement.

## Usage

Usage string (verbatim): `./rk_mpi_tde_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT] [-W DST_WIDTH] [-H DST_HEIGHT]...`. Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim; tabs/newlines condensed):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-i` | `--input` | str | input file name. e.g.(/userdata/1080p.nv12). \<required\> |
| `-w` | `--src_width` | int | src width. e.g.(1920). \<required\> |
| `-h` | `--src_height` | int | src height. e.g.(1080). \<required\> |
| — | `--src_vir_width` | int | src vir width. e.g.(1920). |
| — | `--src_vir_height` | int | src vir height. e.g.(1080). |
| — | `--src_compress` | int | src compress mode. e.g.(1). |
| `-W` | `--dst_width` | int | dst width. e.g.(1920). \<required\> |
| `-H` | `--dst_height` | int | dst height. e.g.(1080). \<required\> |
| — | `--dst_compress` | int | dst compress mode. e.g.(1). |
| `-o` | `--output` | str | output file path. e.g.(/userdata/tde/). default(NULL). |
| `-n` | `--loop_count` | int | loop running count. can be any count. default(1) |
| `-j` | `--job_number` | int | the job number of vgs. default(1). |
| `-t` | `--task_number` | int | the task number of one job. default(1). |
| `-f` | `--src_format` | int | src pixel format. default(0. 0 is NV12). |
| `-F` | `--dst_format` | int | dst pixel format. default(0. 0 is NV12). |
| `-p` | `--operation` | int | operation type. default(0). 0: quick copy. 1: quick resize. 2: quick fill. 3: rotation. 4: mirror and flip. 5: colorkey. |
| — | `--src_rect_x` | int | src rect x. default(0). |
| — | `--src_rect_y` | int | src rect y. default(0). |
| — | `--src_rect_w` | int | src rect width. default(src_width). |
| — | `--src_rect_h` | int | src rect height. default(src_height). |
| — | `--dst_rect_x` | int | dst rect x. default(0). |
| — | `--dst_rect_y` | int | dst rect y. default(0). |
| — | `--dst_rect_w` | int | dst rect width. default(dst_width). |
| — | `--dst_rect_h` | int | dst rect height. default(dst_height). |
| `-c` | `--fill color` | int | fill color. default(0). |
| `-r` | `--rotation` | int | rotation angle. default(0). 0: 0. 1: 90. 2: 180. 3: 270 |
| `-m` | `--mirror` | int | mirror or flip. default(0). 0: none. 1: flip. 2: mirror. 3: both |

Notes:

- The long name of the fill-colour option contains a space (`"fill color"`), so in practice only `-c` works.
- `main` requires five fields to be non-zero (`input`, `src_width`, `src_height`, `dst_width`, `dst_height`: five `cmp r3,#0; beq usage` checks). Otherwise it prints `argparse_usage`.
- `test_tde_set_default_paramter` fills the rect defaults (src/dst rect = full width/height) after parsing.

## How it works

1. argparse → `test_tde_set_default_paramter` → `cmd parse result: ` plus `input  file name`, `job number`, `task number`, `operation type` and the other fields.
2. `RK_MPI_SYS_Init` → `RK_TDE_Open` → for `loop_count` iterations: `Running mpi tde test loop count %d.` → `test_tde_job(ctx)` → `RK_TDE_Close` → `RK_MPI_SYS_Exit` (`test running ok!` / `test runnning failed!`).
3. Source loading (`test_tde_load_src_file`): `RK_MPI_CAL_TDE_GetPicBufferSize`, `RK_MPI_SYS_MmzAlloc`, `fopen(input,"rb+")` + `fread`, `RK_MPI_SYS_MmzFlushCache`, `RK_MPI_CAL_COMM_GetHorStride`, `RK_MPI_MB_SetBufferStride`. Destination buffers are allocated with `RK_MPI_SYS_MmzAlloc`.
4. `test_tde_job`: for each of `job_number` jobs it calls `RK_TDE_BeginJob`, then `test_tde_add_task` `task_number` times, dispatching on `operation`:
   - 0 → `RK_TDE_QuickCopy`
   - 1 → `RK_TDE_QuickResize`
   - 2 → `RK_TDE_QuickFill` (with fill colour; the destination is pre-filled by `memcpy` from the source)
   - 3 → `RK_TDE_Rotate`
   - 4/5 → `RK_TDE_Bitblit` with an `rkTDE_OPT_S` (mirror/flip or colour key) (`test_tde_bit_blit_task`)
   - any other value → `unknown operation type %d` + `RK_TDE_CancelJob`

   Each task prints `src surface w: %d h %d fmt: %d com: %d  rect x: %d y: %d w: %d h: %d`. The job finishes with `RK_TDE_EndJob` and `RK_TDE_WaitForDone`.

5. `test_tde_save_result`: when `--output` is set, writes each destination surface to `"%s%s_%dx%d_%d.bin"` (output prefix + name + size + index) with `fopen("wb+")`/`fwrite`, then frees the buffers with `RK_MPI_SYS_Free`.

## Interfaces touched

- Device nodes / sysfs / procfs: none referenced directly. TDE/RGA and MMZ access go through librockit (`/dev/mpi/vrga`, `/dev/mpi/valloc`, `/dev/ion` strings in librockit.so) [INFERENCE].
- Files and paths read/written: reads `--input`. Writes `<--output><name>_<W>x<H>_<n>.bin`.
- Network: none.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. There are no references to `rk_mpi_tde_test` in `downlaods/3/dump/` other than the binary itself, and `lp_app` does not depend on it. It works only on files and memory. Running it concurrently with `lp_app` merely shares the RGA engine and MMZ memory [INFERENCE]. It has no side effects beyond writing output files.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_tde_test | grep -E 'TDE|SYS|MB_'
 RK_TDE_Open Close BeginJob EndJob CancelJob WaitForDone QuickCopy QuickFill QuickResize Rotate Bitblit
 RK_MPI_CAL_TDE_GetPicBufferSize RK_MPI_SYS_Init Exit MmzAlloc MmzFlushCache Free RK_MPI_MB_GetSize SetBufferStride Handle2VirAddr
internal functions: test_tde_save_result, unit_test_tde_get_size, test_tde_read_file, test_tde_fill_src/dst,
 test_tde_quick_copy_resize_rotate_task, test_tde_quick_fill_task, test_tde_bit_blit_task, test_tde_add_task,
 test_tde_job, test_tde_load_src_file, test_tde_set_default_paramter
main: 11e0c..11e44 five "cmp r3,#0; beq argparse_usage" ; bl RK_MPI_SYS_Init ; bl RK_TDE_Open ; bl test_tde_job ; bl RK_TDE_Close
$ strings -t x rk_mpi_tde_test
 4e70 ./rk_mpi_tde_test [-i SRC_PATH] [-w SRC_WIDTH] [-h SRC_HEIGHT] [-W DST_WIDTH] [-H DST_HEIGHT]...
 "%s%s_%dx%d_%d.bin"  "unknown operation type %d"
```

## Open questions

- The exact mapping of operations 4 and 5 to `rkTDE_OPT_S` fields (mirror vs. colour key) was inferred from the help text and the `test_tde_bit_blit_task` signature, not traced field by field [INFERENCE].
- The exact second `%s` in the output filename format was not resolved.
