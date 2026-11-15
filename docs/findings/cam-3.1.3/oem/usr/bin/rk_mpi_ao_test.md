# `rk_mpi_ao_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_ao_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `26288` |
| sha256 | `a2e67fd8ba87c13f39311da188ddfca24803ab682a20aab63ed4e827ea25666c` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_ao_test` [INFERENCE: matches SDK naming and argparse test skeleton] |
| confidence | high |

## Summary

This is a Rockchip MPI test for audio output (AO). It plays a raw PCM file to the sound card through `RK_MPI_AO_*`. Mode 1 instead decodes a G.726 file with ADEC bound to AO. It can also exercise volume, mute, track mode, pause/resume, buffer clearing, attribute get/clear, channel statistics and the AO "save file" feature. It is an SDK test tool, and nothing on the camera calls it.

## Usage

The option table below was rebuilt from the argparse table that `main` builds on the stack, and from the defaults in `main` (`calloc(184,1)` plus a literal pool at 0x11e00 = `(1,1,48000,0,0,2,16,0,100,…)`).

```
./rk_mpi_ao_test [-i src_path] [--device_rate rate] [--device_ch ch] [--input_rate rate] [--input_ch ch]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-i` | `--input` | str | input file name , e.g.(./*.pcm). <required> | NULL |
| | `--input_ch` | int | the sample rate of input data. <required> (sic, the text says "sample rate" but this is the channel count) | 0 |
| | `--input_rate` | int | the sample rate of input data. <required> | 0 |
| | `--device_ch` | int | the number of sound card channels. default(2). | 2 |
| | `--device_rate` | int | the sample rate of open sound card.  default(48000). | 48000 |
| `-o` | `--output` | str | output file name, e.g.(./ao). default(NULL). | NULL |
| `-n` | `--loop_count` | int | loop running count. can be any count. default(1) | 1 |
| `-c` | `--channel_count` | int | the count of ao channel. default(1). | 1 |
| | `--bit` | int | the bit width of open sound card, range(8, 16, 24), default(16) | 16 |
| | `--period_size` | int | the period size for open sound card, default(1024) | 1024 |
| | `--period_count` | int | the period count for open sound card, default(4) | 4 |
| | `--sound_card_name` | str | the sound name for open sound card, default(NULL) | NULL |
| | `--set_volume` | int | set volume test, range(0, 100), default(100) | 100 |
| | `--set_mute` | int | set mute test, range(0, 1), default(0) | 0 |
| | `--set_fade` | int | set fade rate, range(0, 7), default(0) | 0 |
| | `--set_track_mode` | int | set track mode test, range(0:normal, 1:both_left, 2:both_right, 3:exchange, 4:mix,5:left_mute, 6:right_mute, 7:both_mute), default(0) | 0 |
| | `--get_volume` | int | get volume test, range(0, 1), default(0) | 0 |
| | `--get_mute` | int | get mute test, range(0, 1), default(0) | 0 |
| | `--get_track_mode` | int | get track mode test, range(0, 1), default(0) | 0 |
| | `--query_stat` | int | query ao statistics info, range(0, 1), default(0) | 0 |
| | `--pause_resume` | int | test ao chn pause and resume function, range(0, 1), default(0) | 0 |
| | `--save_file` | int | test ao save file, if enabled, must set output file, range(0, 1), default(0) | 0 |
| | `--query_file_stat` | int | query file status, range(0, 1), default(0) | 0 |
| | `--clr_buf` | int | clear buffer of channel, range(0, 1), default(0) | 0 |
| | `--clr_attr` | int | clear attribute of channel, range(0, 1), default(0) | 0 |
| | `--get_attr` | int | get attribute of device, range(0, 1), default(0) | 0 |
| | `--loopback_mode` | int | configure the loopback mode during ao runtime | 0 |
| `-m` | `--mode` | int | test mode(default 0; 0:ao send frame 1:adec(g726) bind one ao | 0 |
| | `--enc_path` | str | adec input file name , e.g.(./*.g726). <required> | NULL |

`main` prints "cmd parse result:", checks the required inputs (it branches to `argparse_usage` if they are missing) and then runs the selected mode. Any other mode prints "no support such test mode:%d".

## How it works

1. `RK_MPI_SYS_Init`.
2. **Mode 0** (`unit_test_mpi_ao`, run `loop_count` times):
   - `test_open_device_ao`: copies the card name with `snprintf`, validates bit width and channel count, then calls `RK_MPI_AO_SetPubAttr` and `RK_MPI_AO_Enable`.
   - For each channel it calls `RK_MPI_AO_SetChnParams` and then `test_init_mpi_ao`, which does `RK_MPI_AO_EnableChn` and, if the input rate differs from the device rate, `RK_MPI_AO_EnableReSmp`.
   - Two threads run:
     - `sendDataThread` opens `-i` ("rb") and reads chunks with `fread`. It wraps each chunk with `RK_MPI_SYS_CreateMB`, calls `RK_MPI_AO_SendFrame` (retried on failure: "send frame fail, result = %d…") and then `RK_MPI_MB_ReleaseMB`. At EOF it logs "eof" and calls `RK_MPI_AO_WaitEos`.
     - `commandThread` calls `RK_MPI_AO_SetMute`/`SetVolume`, `SetTrackMode`, `GetVolume`/`GetMute`/`GetTrackMode`. It also calls `query_ao_flow_graph_stat` (`RK_MPI_AO_QueryChnStat`: total, free and busy channel buffers).
     - If `save_file` is set, `commandThread` calls `RK_MPI_AO_SaveFile` with file name `ao_save_file.bin` under the `-o` path, and `RK_MPI_AO_QueryFileStatus`.
     - If `pause_resume` is set, it sleeps with `usleep`, then calls `RK_MPI_AO_PauseChn` ("pause test") and `RK_MPI_AO_ResumeChn` ("resume test").
     - It also calls `RK_MPI_AO_ClearChnBuf`, `RK_MPI_AO_ClrPubAttr`, and `RK_MPI_AO_GetPubAttr` (which logs "input stream rate", "open sound card rate" and "open sound card channel").
   - Teardown: `RK_MPI_AO_DisableReSmp`, `RK_MPI_AO_DisableChn`, `RK_MPI_AO_Disable`.
3. **Mode 1** (`test_adec_bind_ao_loop`):
   - It opens and enables AO as above, calls `RK_MPI_AO_SetTrackMode`, then `RK_MPI_ADEC_CreateChn` (G.726 per the help text) and `RK_MPI_SYS_Bind` from ADEC to AO.
   - `send_stream_thread` reads `--enc_path` and feeds it with `RK_MPI_SYS_CreateMB` and `RK_MPI_ADEC_SendStream`, ending with `RK_MPI_ADEC_SendEndOfStream` ("read eos packet, now send eos packet!").
   - Teardown: `pthread_join`, `RK_MPI_SYS_UnBind`, `deinit_mpi_ao`, `RK_MPI_ADEC_DestroyChn`. On a bind failure the log message wrongly reads "===bind ai to aenc failed===" (copy-paste in the source).
4. `RK_MPI_SYS_Exit`.

## Interfaces touched

- Device nodes / sysfs / procfs: the ALSA playback PCM and control device through librockit (`/dev/snd/pcmC%uD%u%c`, `/dev/snd/controlC%u` in librockit.so). On this camera the only card is card 0, `platform-acodec-sound` (internal acodec; udev data for c116:16 = pcmC0D0p). rockit's `/dev/mpi/*` kernel interface [INFERENCE].
- Files and paths read/written:
  - reads `-i` PCM file;
  - reads `--enc_path` (G.726) in mode 1;
  - writes `<-o>/ao_save_file.bin` via `RK_MPI_AO_SaveFile` when `--save_file 1`.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot or referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_ao_test` matches only the binary itself, and neither `RkLunch.sh` nor any init script references it. Running it manually would play audio through the acodec line/speaker output if a speaker is fitted [INFERENCE]. It could conflict with `lp_app` if `lp_app` owns AO or the ALSA PCM. Volume, mute and track-mode changes affect the AO device while the test runs. It has no flash, GPIO or reboot side effects.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_AO_{SetPubAttr,GetPubAttr,ClrPubAttr,Enable,Disable,EnableChn,DisableChn,SetChnParams,EnableReSmp,DisableReSmp,SendFrame,WaitEos,PauseChn,ResumeChn,ClearChnBuf,QueryChnStat,SaveFile,QueryFileStatus,SetVolume,GetVolume,SetMute,GetMute,SetTrackMode,GetTrackMode}`, `RK_MPI_ADEC_{CreateChn,DestroyChn,SendStream,SendEndOfStream}`, `RK_MPI_SYS_{Init,Exit,Bind,UnBind,CreateMB}`, `RK_MPI_MB_ReleaseMB`.
- Exported: `test_open_device_ao`, `test_init_mpi_ao`, `sendDataThread`, `commandThread`, `query_ao_flow_graph_stat`, `deinit_mpi_ao`, `test_close_device_ao`, `unit_test_mpi_ao`, `test_adec_bind_ao_loop`, `send_stream_thread`.
- Disassembly of `commandThread`:
  ```
  12d08 movt r12,#1 ; "ao_save_file.bin"
  12d54 bl RK_MPI_AO_SaveFile
  12dcc bl RK_MPI_AO_PauseChn
  12e04 bl RK_MPI_AO_ResumeChn
  ```
- Default literal pool at 0x11e00: `(1, 1, 48000, 0, 0, 2, 16, 0, 100, 0, …)`.
- `dump/dev/snd/by-path/platform-acodec-sound -> ../controlC0`.

## Open questions

- Which ALSA PCM librockit opens when `--sound_card_name` is NULL is not visible in this binary.
- Whether the camera has a speaker or amplifier on the acodec output is unknown.
- The `loopback_mode` value semantics are not documented in the binary.
