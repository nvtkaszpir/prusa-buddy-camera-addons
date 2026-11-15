# `rk_mpi_adec_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_adec_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `18020` |
| sha256 | `d7046e71a5a6834de80619aa7e26170ac8ea2e229798c13bbd01d59aaa7e6ac7` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_adec_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

This is a file-to-file test of rockit's software audio decoder (ADEC). It reads an encoded audio file (MP2, G.726, G.711A or G.711U), pushes it into `RK_MPI_ADEC` channels and writes the decoded PCM to a file. It can optionally query channel statistics and clear channel buffers. It does not use the sound card. It is an SDK developer tool.

## Usage

The option table was rebuilt from the argparse table built in `main`. Defaults come from `main`: `malloc(56)` followed by `memset` and stores (loop=1, channels=1, other values 0).

```
./rk_mpi_adec_test [-i src_path] [-C name] [--input_rate rate] [--input_ch ch]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-i` | `--input` | str | input file name , e.g.(./*.mp3). <required> | NULL |
| `-C` | `--codec` | str | codec, e.g.(mp2/g711a/g711u/g726). <required> | NULL |
| | `--input_ch` | int | the number of input stream channels. <required> | 0 |
| | `--input_rate` | int | the sample rate of input stream. <required> | 0 |
| `-o` | `--output` | str | output file name, e.g.(./*.pcm). default(NULL). | NULL |
| `-n` | `--loop_count` | int | loop running count. default(1) | 1 |
| `-c` | `--channel_count` | int | the count of adec channel. default(1). | 1 |
| | `--dec_mode` | int | the audio stream decode mode, range(0: pack mode, 1: stream mode), default(0) | 0 |
| | `--query_stat` | int | query adec statistics info, range(0: query, 1: not query), default(0) | 0 |
| | `--clr_buf` | int | clear buffer of channel, range(0, 1), default(0) | 0 |

`-C` is matched with `strstr` against `mp2`, `g726`, `g711a` and `g711u` in `test_init_mpi_adec`. Anything else logs "test not find codec id : %s". There is no `mp3` string in this binary, so the `*.mp3` example in the help is only an example.

## How it works

1. `main` parses the options, prints "cmd parse result:", calls `RK_MPI_SYS_Init` and runs `unit_test_mpi_adec` `loop_count` times ("start/end running loop count = %d").
2. `unit_test_mpi_adec` checks the channel count ("adec chn(%d) > max_chn(%d)") and, for each channel:
   - `test_init_mpi_adec` allocates the attributes with `calloc`, maps the codec, applies `dec_mode` (pack or stream) and calls `RK_MPI_ADEC_CreateChn`.
   - `send_stream_thread` opens `-i` ("rb"), reads packets with `fread`, and wraps them with `RK_MPI_SYS_CreateMB`, `RK_MPI_ADEC_SendStream` and `RK_MPI_MB_ReleaseMB`. At EOF it calls `RK_MPI_ADEC_SendEndOfStream` ("read eos packet, now send eos packet!").
   - `receive_data_thread` opens `-o` ("wb+") and loops on `RK_MPI_ADEC_GetFrame`, `RK_MPI_MB_Handle2VirAddr` ("get frame data = %p, size = %d"), `fwrite`/`fflush` and `RK_MPI_ADEC_ReleaseFrame`.
     - When `query_stat` is set it calls `query_adec_flow_graph_stat`, which uses `RK_MPI_ADEC_QueryChnStat` and logs "EOS flag", "total/free/busy number of channel buffer".
     - When `clr_buf` is set it calls `RK_MPI_ADEC_ClearChnBuf` ("test clear chn(%d) buf").
     - The loop stops on "get eos packet.".
   - It then calls `pthread_join`, `RK_MPI_ADEC_DestroyChn` and `free`. A leftover developer message also appears: "please add code here to free pstResv".
3. `register_ext_adec` registers an external decoder `ext_g711a` with `RK_MPI_ADEC_RegisterDecoder`, but nothing calls it. `main` calls `RK_MPI_ADEC_UnRegisterDecoder` at exit when a handle is stored ("unregister ext audio decoder").
4. `RK_MPI_SYS_Exit`.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. librockit uses `/dev/mpi/*` [INFERENCE]. No ALSA access.
- Files and paths read/written: reads the `-i` encoded audio file; writes the `-o` PCM output.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_adec_test` matches only the binary itself. The test is file-based, so the only interaction with `lp_app` is shared MPI resources (ADEC channels, MB memory). It has no hardware side effects.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_ADEC_{CreateChn,DestroyChn,SendStream,SendEndOfStream,GetFrame,ReleaseFrame,QueryChnStat,ClearChnBuf,RegisterDecoder,UnRegisterDecoder}`, `RK_MPI_SYS_{Init,Exit,CreateMB}`, `RK_MPI_MB_{Handle2VirAddr,ReleaseMB}`.
- Exported: `test_init_mpi_adec`, `test_deinit_mpi_adec`, `unit_test_mpi_adec`, `query_adec_flow_graph_stat`, `register_ext_adec`, `unregister_ext_adec`.
- Disassembly of `test_init_mpi_adec`:
  ```
  11f28 movt r1,#1 ; "mp2"    bl strstr
  11f60 bl RK_MPI_ADEC_CreateChn
  11f7c "g726" / 11f98 "g711a" / 11fb4 "g711u"   bl strstr
  ```
- `receive_data_thread`:
  ```
  11db0 bl RK_MPI_ADEC_GetFrame … 11df0 bl query_adec_flow_graph_stat … 11e30 bl RK_MPI_ADEC_ClearChnBuf
  ```

## Open questions

- The help text for `query_stat` says "0: query, 1: not query", but the code does the opposite. At 0x11ddc it runs `ldr r3,[r4,#40]; cmp r3,#0; beq skip; bl query_adec_flow_graph_stat; str #0,[r4,#40]`, so a nonzero value queries once and then clears the flag. `clr_buf` (ctx+44) is not reset, so it clears the buffer on every received frame while set.
- Which decoders the shipped librockit actually provides is not determinable from this binary.
