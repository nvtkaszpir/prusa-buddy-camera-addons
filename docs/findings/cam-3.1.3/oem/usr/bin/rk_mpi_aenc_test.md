# `rk_mpi_aenc_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_aenc_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `18024` |
| sha256 | `baa2935cd33ca74fdf7549d3562a1248108f6d060d5c2d37148b6cb306307d31` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_aenc_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

This is a file-to-file test of rockit's software audio encoder (AENC). It reads raw PCM from a file, sends it to `RK_MPI_AENC` channels, and writes the encoded bitstream (MP2, MP3, G.726, G.711A or G.711U) to a file. It does not touch the sound card. It is an SDK developer tool.

## Usage

The option table was rebuilt from the argparse table built in `main`. Defaults come from `main`: `malloc(56)` followed by `memset` and explicit stores (loop=1, channels=1, input_format=16, frame_size=1024).

```
./rk_mpi_aenc_test [-i src_path] [-C name] [--input_rate rate] [--input_ch ch] [--input_format format]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-i` | `--input` | str | input file name , e.g.(./*.mp3). <required> | NULL |
| `-C` | `--codec` | str | codec, e.g.(mp3/mp2/g711a/g726). <required> | NULL |
| | `--input_ch` | int | the number of input stream channels. <required> | 0 |
| | `--input_rate` | int | the sample rate of input stream. <required> | 0 |
| | `--input_format` | int | the input format of input stream. <required> | 16 |
| `-o` | `--output` | str | output file name, e.g.(./*.pcm). default(NULL). | NULL |
| `-n` | `--loop_count` | int | loop running count. default(1) | 1 |
| `-c` | `--channel_count` | int | the count of adec channel. default(1). | 1 |
| | `--frame_size` | int | the size of send frame. default(1024). | 1024 |

Notes:

- `--input_format` is the PCM bit width. `test_init_mpi_aenc` accepts only 8, 16 or 24 and otherwise logs "test not find format : %s".
- `-C` is matched with `strstr` against `mp2`, `mp3`, `g726`, `g711a` and `g711u`. Anything else logs "test not find codec id : %s".
- `main` refuses to run (prints usage) unless input, input_ch, input_rate and codec are set.
- The example file names in the help (`*.mp3` for input, `*.pcm` for output) are reversed relative to what the code does, which is copy-paste from the ADEC test.

## How it works

1. `main` parses the options, prints "cmd parse result:", calls `RK_MPI_SYS_Init` and runs `unit_test_mpi_aenc` `loop_count` times.
2. `unit_test_mpi_aenc` checks the channel count ("aenc chn(%d) > max_chn(%d)") and, for each channel:
   - `test_init_mpi_aenc` maps codec and bit width, then calls `RK_MPI_AENC_CreateChn` ("create aenc chn %d err:0x%x").
   - `send_frame_thread` opens `-i` ("rb") and reads `frame_size` bytes at a time with `fread`. It computes a timestamp from rate, channels and bytes (`__aeabi_uldivmod`), then wraps the chunk with `RK_MPI_SYS_CreateMB`, calls `RK_MPI_AENC_SendFrame` and `RK_MPI_MB_ReleaseMB`. At EOF it sends an EOS frame ("read eos frame, now send eos frame!").
   - `receive_stream_thread` opens `-o` ("wb+") and loops on `RK_MPI_AENC_GetStream`, `RK_MPI_MB_Handle2VirAddr`, `fwrite`/`fflush` and `RK_MPI_AENC_ReleaseStream`, until "get eos stream.".
   - It then calls `pthread_join` and `RK_MPI_AENC_DestroyChn`.
3. The binary contains `register_ext_aenc`, which registers an external encoder named `ext_g711a` via `RK_MPI_AENC_RegisterEncoder`, and `unregister_ext_aenc`. No `bl` instruction calls `register_ext_aenc`. `main` calls `RK_MPI_AENC_UnRegisterEncoder` on exit only when the stored handle is not -1.
4. `RK_MPI_SYS_Exit`.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. librockit uses `/dev/mpi/*` for the system/MB allocator [INFERENCE]. No ALSA access.
- Files and paths read/written: reads the `-i` PCM file; writes the `-o` encoded file.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot. The only file in `downlaods/3/dump/` that contains `rk_mpi_aenc_test` is the binary itself. The test is purely file-based, so it does not contend for the sound card. It only uses MPI system resources (AENC channels and MB memory) alongside `lp_app`. It has no side effects beyond the output file.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_AENC_{CreateChn,DestroyChn,SendFrame,GetStream,ReleaseStream,RegisterEncoder,UnRegisterEncoder}`, `RK_MPI_SYS_{Init,Exit,CreateMB}`, `RK_MPI_MB_{Handle2VirAddr,ReleaseMB}`, `poll`, `pthread_create`.
- Exported: `register_ext_aenc`, `unregister_ext_aenc`, `test_init_mpi_aenc`, `unit_test_mpi_aenc`, `test_aenc_poll_event`. Strings: `send_frame_thread`, `receive_stream_thread`.
- Disassembly of `test_init_mpi_aenc`:
  ```
  11fa8 movt r1,#1 ; "mp2"   bl strstr
  11fc8 ldr r3,[r4,#24] ; cmp #8 / #16 / #24   (input_format = bit width)
  12088 "mp3" / 120a4 "g726" / 120c0 "g711a" / 120dc "g711u"  bl strstr
  1206c bl RK_MPI_AENC_CreateChn
  ```
- `llvm-objdump -d … | grep 'bl.*register_ext'` returned no callers.

## Open questions

- Whether the shipped librockit actually has encoders for MP2/MP3 (versus only G.711/G.726) cannot be determined from this binary alone.
- The meaning of the ctx field checked against -1 before unregistering is unclear (the stored value appears to be the frame-size constant).
