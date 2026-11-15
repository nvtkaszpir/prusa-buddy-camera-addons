# `rk_mpi_af_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_af_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `17952` |
| sha256 | `edc1f542ceadb6d3f5dc4c406d1a795cdc043ef71b9278542ccc372c0ad0c970` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_af_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

This is a file-to-file test of rockit's audio filter (AF) module, `RK_MPI_AF_*`. It supports two filter types, chosen with `--af_type`:

- `resample`: sample-rate, channel and bit-width conversion. librockit implements this with a Speex resampler (`RTAFilterSpeexResample`).
- `3a`: the voice "3A" processing chain (AEC/beamforming/ANR/AGC) configured from a JSON patch file. Inside librockit this is backed by `libaec_bf_process.so` [INFERENCE].

It reads interleaved PCM from a file and writes the filtered PCM to another file. It does not use the sound card.

## Usage

The option table was rebuilt from the argparse table built in `main`. Defaults come from `main`: `malloc(72)` followed by `memset`, then loop_count=1 and the channel count at ctx+56 = 1.

```
./rk_mpi_af_test [-i src_path] [-o dst_patch] [--af_type af_type] [--input_rate rate] [--input_ch ch]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-i` | `--input` | str | input file name , e.g.(./*.pcm). <required> | NULL |
| `-o` | `--output` | str | output file name, e.g.(./ao). default(required). | NULL |
| | `--af_type` | str | set audio filter type, default(required) | NULL (`resample` or `3a`) |
| | `--3a_cfgs` | str | 3a configs patch, default(NULL) | NULL |
| | `--input_rate` | int | the sample rate of input data. <required> | 0 |
| | `--input_ch` | int | the channels of input data. <required> | 0 |
| | `--input_bit` | int | the bit width of input data. <required> | 0 |
| | `--out_rate` | int | the sample rate of out data. <required> | 0 |
| | `--out_ch` | int | the channels of out data. <required> | 0 |
| | `--out_bit` | int | the bit width of out data. <required> | 0 |
| | `--input_ch_layout` | int | the channels layout of input data. <required> | 0 |
| | `--input_rec_layout` | int | the mic channels layout of input data. <required> | 0 |
| | `--input_ref_layout` | int | the ref channels layout of input data. <required> | 0 |
| `-n` | `--loop_count` | int | loop running count. can be any count. default(1) | 1 |

`mpi_af_test_show_options` prints "cmd parse result:" followed by every value. The layouts are bitmasks of which interleaved channels are microphone (`rec`) and which are echo-reference (`ref`) channels for AEC [INFERENCE: inferred from the option names].

## How it works

1. `main` parses the options and prints them, logs "ctx->srcFilePath : %s, ctx->chAfType: %s, …", checks the required fields and calls `RK_MPI_SYS_Init`. It then runs the test `loop_count` times ("af chn(%d) > max_chn(%d)" guard).
2. `test_init_af` picks the init routine with `strstr(af_type, "resample")` or `strstr(af_type, "3a")`:
   - `test_init_af_resample` fills the input/output rate, channels and bit width, validating them ("bitwidth(%d) not support"), then calls `RK_MPI_AF_Create`.
   - `test_init_af_ag` (the "3a" path) copies `--3a_cfgs` into the attributes with `snprintf("%s")`, sets the formats and layouts, then calls `RK_MPI_AF_Create` ("create af chn %d err:0x%x").
3. Two threads run:
   - `send_af_thread` reads the input in chunks ("rb", `fread`). It wraps each chunk with `RK_MPI_SYS_CreateMB`, calls `RK_MPI_AF_SendFrame` ("send frame error, seq = %d") and `RK_MPI_MB_ReleaseMB`. It logs "eof" at the end.
   - `receive_af_thread` opens the output ("wb+") and loops on `RK_MPI_AF_GetFrame`, `RK_MPI_MB_Handle2VirAddr` ("get frame (size: %d, outdata: %p)"), `fwrite` and `RK_MPI_AF_ReleaseFrame`, until "get eos stream.".
4. Teardown: `pthread_join`, `RK_MPI_AF_Destroy` (`test_deinit_af`), then `RK_MPI_SYS_Exit`.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. librockit uses `/dev/mpi/*` for MB allocation [INFERENCE]. No ALSA access.
- Files and paths read/written: reads the `-i` PCM file; writes the `-o` PCM file; reads the `--3a_cfgs` JSON config through librockit. The device ships `/oem/usr/share/vqefiles/config_aivqe.json` (sections `aec`, `bf`, `fast_aec`, `aes`, `gsc`, `agc`, `anr`, `nlp`, …) and `config_aoagc.json`, which are the natural candidates [INFERENCE].
- Network: none.
- Environment variables / config files: `--3a_cfgs` JSON.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_af_test` matches only the binary itself. It is a pure offline file-processing test, useful for running the camera's audio 3A chain on recorded PCM. It does not conflict with `lp_app` beyond shared MPI memory, and it has no hardware side effects.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_AF_{Create,Destroy,SendFrame,GetFrame,ReleaseFrame}`, `RK_MPI_SYS_{Init,Exit,CreateMB}`, `RK_MPI_MB_{Handle2VirAddr,ReleaseMB}`.
- Exported: `test_init_af`, `test_init_af_resample`, `test_init_af_ag`, `test_deinit_af`, `send_af_thread`, `receive_af_thread`, `unit_test_mpi_af`, `mpi_af_test_show_options`.
- Disassembly of `test_init_af`:
  ```
  120e4 movt r1,#1 ; "resample"   bl strstr  -> bl test_init_af_resample
  12110 movt r1,#1 ; "3a"         bl strstr  -> bl test_init_af_ag
  ```
- librockit.so strings: `RTAFilterSpeexResample`, `af_resample`, `af_type`. librockit's DT_NEEDED includes `libaec_bf_process.so` and `librkaudio_detect.so`.

## Open questions

- The exact JSON schema `--3a_cfgs` expects (a full file versus a "patch" of overrides) is not visible in this binary. The help calls it a "configs patch".
- The layout bitmask semantics are [INFERENCE] from the option names.
