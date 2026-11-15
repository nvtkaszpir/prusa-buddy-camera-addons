# `rk_mpi_avio_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_avio_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `13848` |
| sha256 | `00d43db55ea03e78f0eaf594934246e61e473a8a598b7c15535d0371d1489b3f` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_avio_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

"AVIO" is not a hardware block or an I/O device. In this binary it is a small self-test of the audio/video I/O data structures. The internal function name `unit_test_mpi_vaio_struct` and the use of `rkVDEC_STREAM_S` show that it checks how a stream packet (`VDEC_STREAM_S`) can wrap an MB (media buffer) created in three different ways:

- an MMZ allocation;
- a user `malloc` buffer with a free callback;
- a user `malloc` buffer without a callback.

For each case it prints the MB, virtual address, fd, length, PTS and EOS flag, then frees the buffer. It has no options and touches no device beyond the buffer allocator.

## Usage

The argparse table is a static `.data` copy containing only `help` and the "basic options:" group. `main` always calls `argparse_usage` after parsing, so the help text is printed on every run, and then the tests run regardless.

```
[options]: 

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |

## How it works

`main` (0x10e50): `memcpy` of the static options → `argparse_init` → `argparse_describe` → `argparse_parse` → `argparse_usage`. It then calls `test_video_stream(0)`, `test_video_stream(1)` and `test_video_stream(2)` and returns 0. `RK_MPI_SYS_Init` is not called.

`test_video_stream(int mode)`:

- **mode 0**: `RK_MPI_SYS_MmzAlloc(&mb, NULL, NULL, 250)` allocates a 250-byte DMA (MMZ) buffer. The stream struct gets PTS 50 and EOS 0, then `test_dump_vstream_info` runs and `RK_MPI_MB_ReleaseMB(mb)` frees it.
- **mode 1**: `malloc(250)`, then `RK_MPI_SYS_CreateMB` with an external-buffer config whose free callback is `test_video_stream_buffer_free` (0x10ff8, which calls `free`). The length is 100 and the PTS 50. Then `test_dump_vstream_info` runs and `RK_MPI_SYS_Free(mb)`, which lets the callback free the memory.
- **mode 2**: `malloc(250)`, then `RK_MPI_SYS_CreateMB` without a free callback. Then `test_dump_vstream_info`, `RK_MPI_SYS_Free(mb)`, and an explicit `free()`.

`test_dump_vstream_info(VDEC_STREAM_S*)` logs "test dump vtsream info:" and then "mb (%p), data(%p), fd(%d), len(%d), pts(%lld), eos(%d)", using `RK_MPI_MB_Handle2VirAddr` and `RK_MPI_MB_Handle2Fd`.

`unit_test_mpi_vaio_struct()` is exported but `main` does not call it. The work is done through `test_video_stream`.

## Interfaces touched

- Device nodes / sysfs / procfs: none named. librockit's MMZ/MB allocator is used (`/dev/mpi/valloc` or a DMA heap inside librockit) [INFERENCE].
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_avio_test` matches only the binary itself, and no init script or `lp_app.sh` mentions it. It allocates a few hundred bytes and frees them, so it is harmless and has no hardware, flash or GPIO side effects. It is irrelevant to the camera's operation.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_SYS_MmzAlloc`, `RK_MPI_SYS_CreateMB`, `RK_MPI_SYS_Free`, `RK_MPI_MB_Handle2VirAddr`, `RK_MPI_MB_Handle2Fd`, `RK_MPI_MB_ReleaseMB`, `malloc`, `free`.
- Exported (C++ mangled): `_Z17test_video_streami`, `_Z22test_dump_vstream_infoP15rkVDEC_STREAM_S`, `_Z25unit_test_mpi_vaio_structv`, `_Z29test_video_stream_buffer_freePv`.
- Disassembly of `main`:
  ```
  10eb8 bl argparse_usage
  10ebc mov r0,#0 ; 10ec0 bl test_video_stream
  10ec4 mov r0,#1 ; 10ec8 bl test_video_stream
  10ecc mov r0,#2 ; bl test_video_stream
  ```
- Disassembly of `test_video_stream` (PLT entries resolved via `.rel.plt`):
  ```
  110ec mov r0,#250 ; bl malloc ; 11138 movw r3,#4088; movt r3,#1 (=0x10ff8 free cb) ; 11144 bl RK_MPI_SYS_CreateMB
  111e4 mov r3,#250 ; mov r1,r0 ; mov r2,r0 ; 11200 bl RK_MPI_SYS_MmzAlloc ; 11288 bl RK_MPI_MB_ReleaseMB
  112a0 bl malloc ; 112ec bl RK_MPI_SYS_CreateMB ; 11374 bl RK_MPI_SYS_Free ; 11384 bl free
  ```
- `readelf -s librockit.so | grep -i avio/vaio` returned no matches, so there is no AVIO module in librockit.

## Open questions

- Whether "avio" in the file name stands for "audio/video I/O" is [INFERENCE] from the internal name `vaio_struct`. Only the video-stream struct is exercised.
