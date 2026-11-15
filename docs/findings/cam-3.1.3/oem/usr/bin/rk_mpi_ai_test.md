# `rk_mpi_ai_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_ai_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30432` |
| sha256 | `2abf9a27267d255661496a9a07f4522ed921a65a8082e7fcd0bc678283948e21` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_ai_test` (`test/rk_mpi_ai_test.cpp` in the rockit SDK) [INFERENCE: name, argparse layout and C++ symbols match the SDK test pattern] |
| confidence | high |

## Summary

This is a Rockchip MPI test for audio input (AI). It opens the ALSA capture device through rockit's `RK_MPI_AI_*` API, reads PCM frames and can save them to a file. It can also exercise volume, mute and track-mode controls, resampling, VQE (voice quality enhancement, done by `libaec_bf_process.so` inside librockit), AED (acoustic event / loud-sound detection) and BCD (baby-cry detection). In mode 1 it binds AI to an audio encoder (AENC: G.711A or G.726) and writes the encoded stream to a file. It is a developer/factory test shipped with the SDK. Nothing on the camera calls it.

## Usage

The program uses the embedded `argparse` library (cofyc/argparse); `--help` prints the option list. I rebuilt the option table from the `argparse_option` array that `main` builds on the stack (type, short name, long name, help text). Defaults come from the context-initialisation code in `main` (`calloc(176,1)` plus literal-pool constants), and they match the "default(...)" text in the help.

```
./rk_mpi_ai_test [--device_rate rate] [--device_ch ch] [--out_rate rate] [--out_ch ch] [--aed_enable] [--bcd_enable] [--vqe_enable] [--vqe_cfg]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| | `--device_rate` | int | the sample rate of open sound card.  <required> | 0 (must be >0) |
| | `--device_ch` | int | the number of sound card channels. <required>. | 0 (must be >0) |
| | `--out_ch` | int | the channels of out data. <required> | 0 (must be >0) |
| | `--out_rate` | int | the sample rate of out data. <required> | 0 (must be >0) |
| `-o` | `--output` | str | output file name, e.g.(./ai). default(NULL). | NULL |
| `-n` | `--loop_count` | int | loop running count. can be any count. default(1) | 1 |
| `-c` | `--channel_count` | int | the count of adec channel. default(1). | 1 |
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
| | `--aed_enable` | int | the aed enable, 0:disable 1:enable. default(0). | 0 |
| | `--bcd_enable` | int | the bcd enable, 0:disable 1:enable. default(0). | 0 |
| | `--vqe_gap` | int | the vqe gap duration in milliseconds. only supports 16ms or 10ms. default(16). | 16 |
| | `--vqe_enable` | int | the vqe enable, 0:disable 1:enable. default(0). | 0 |
| | `--vqe_cfg` | str | the vqe config file, default(NULL) | NULL |
| | `--loopback_mode` | int | configure the loopback mode during ai runtime | 0 |
| | `--dump_algo` | int | dump algorithm pcm data during ai runtime | 0 |
| `-m` | `--mode` | int | test mode(default 0; 0:ai get&release frame 1:ai bind one aenc(g711a) | 0 |
| | `--aenc_file` | str | aenc file name, e.g.(./userdata/aenc/aenc.g711a). default(NULL). | NULL |
| `-C` | `--codec` | str | codec, e.g.(g711a/g711u/g726). | NULL |

Notes:

- `main` checks the four required rates/channel counts (`device_rate`, `device_ch`, `out_rate`, `out_ch`) and prints usage if any of them is ≤0.
- `--codec` is matched only against `"g726"` and `"g711a"` (`strstr` in `test_init_mpi_aenc`). The help text mentions `g711u`, but there is no `g711u` string in the binary.
- The help text for `-c` says "adec channel", which is a copy-paste leftover. The value is actually the AI channel count.

## How it works

1. `main` allocates the context, builds the argparse table, parses the options and prints a "cmd parse result:" dump (`input  file name`, `open sound rate`, `vqe config file`, `test mode`, …). It installs a SIGINT handler (`signal`, "Catched SIGINT %d") and calls `RK_MPI_SYS_Init`.
2. **Mode 0** (`unit_test_mpi_ai`, repeated `loop_count` times, logging "start/end running loop count = %d"):
   - `test_open_device_ai`: `snprintf` copies the card name into the device attributes. It validates bit width ("bitwidth(%d) not support") and channel count ("channel = %d not support"), then calls `RK_MPI_AI_SetPubAttr` and `RK_MPI_AI_Enable`.
   - For each channel it calls `RK_MPI_AI_SetChnParam`, then `test_init_mpi_ai`, which does:
     - `RK_MPI_AI_EnableChn`;
     - optionally VQE: build the config with `vqe_cfg`, call `RK_MPI_AI_SetVqeAttr`, read it back with `RK_MPI_AI_GetVqeAttr`, compare with `memcmp`, then `RK_MPI_AI_EnableVqe`. Gap check: "Invalid gap: %d, just supports 16ms or 10ms for AI VQE";
     - resampling via `RK_MPI_AI_EnableReSmp` when device and output rates differ ("need to resample %d -> %d");
     - AED via `RK_MPI_AI_SetAedAttr`, `GetAedAttr` and `EnableAed`;
     - BCD via `RK_MPI_AI_SetBcdAttr`, `GetBcdAttr` and `EnableBcd`. A callback `test_bcd_callback` logs "baby cry callback successed".
   - Two threads are created with `pthread_create`:
     - `sendDataThread`: if `-o` was given, it first calls `RK_MPI_AI_SaveFile`, so rockit itself writes `<output>/cap_out.pcm`. It then loops on `RK_MPI_AI_GetFrame`, `RK_MPI_MB_Handle2VirAddr` / `RK_MPI_MB_GetSize` (log "data = %p, len = %d") and `RK_MPI_AI_ReleaseFrame`.
     - With AED enabled, it polls `RK_MPI_AI_GetAedResult` ("aed_result: bAED: %d, bLSD: %d"). With BCD enabled, it polls `RK_MPI_AI_GetBcdResult` ("bcd_result bBCD: %d").
     - When the output rate is 8000 or 16000 and `dump_algo` is set, it also writes `/tmp/cap_aed_2ch.pcm` and `/tmp/cap_bcd_1ch.pcm`. If the rate is anything else, the code clears the dump flag.
     - `commandThread` applies `RK_MPI_AI_SetMute`/`SetVolume`, `SetTrackMode`/`GetTrackMode`, `GetMute` and `GetVolume` according to the `set_*`/`get_*` options and logs "test info : ...".
   - Teardown (`test_deinit_mpi_ai`) calls `RK_MPI_AI_DisableReSmp`, `DisableChn`, `DisableVqe`, `DisableBcd`, `DisableAed` and `RK_MPI_AI_Disable`.
3. **Mode 1** (`test_ai_bind_aenc_loop`, "===test_ai_bind_aenc_loop==="):
   - It opens AI as above and opens `aenc_file` for writing ("wb").
   - `test_init_mpi_aenc` maps `--codec` (g726/g711a) to a codec id ("codecId=%d", "format=%d") and calls `RK_MPI_AENC_CreateChn`.
   - `RK_MPI_SYS_Bind` connects AI to AENC.
   - A thread (entry 0x13250) reads raw frames with `RK_MPI_AI_GetFrame` into `/tmp/cap_out.pcm`.
   - The main loop pulls encoded packets with `RK_MPI_AENC_GetStream`, writes them with `fwrite` and releases them with `RK_MPI_AENC_ReleaseStream`, until "get eos stream.".
   - Teardown: `RK_MPI_SYS_UnBind`, `test_deinit_mpi_ai`, `RK_MPI_AENC_DestroyChn`. On failure the log message wrongly says "RK_MPI_VDEC_DestroyChn fail %x" (copy-paste in the source).
4. At the end it calls `RK_MPI_SYS_Exit`.

The VQE, AED and BCD algorithms are not in this binary. librockit links `libaec_bf_process.so` (AEC/beamforming/ANR/AGC) and `librkaudio_detect.so` (AED/BCD) [INFERENCE: the algorithm split is inferred from the library names and librockit's DT_NEEDED].

## Interfaces touched

- Device nodes / sysfs / procfs: ALSA via librockit, using `/dev/snd/pcmC%uD%u%c` and `/dev/snd/controlC%u` (format strings in librockit.so). The default ALSA name is chosen inside librockit when `--sound_card_name` is NULL; librockit contains `hw:%d,%d`, `hw:7,0` and `hw:7,1`. On this camera the only card is card 0, `platform-acodec-sound` (the RV1106 internal audio codec; `dev/snd/by-path/platform-acodec-sound -> ../controlC0`; udev data for c116:16 and c116:24, i.e. pcmC0D0p and pcmC0D0c). rockit's MPI kernel interface is `/dev/mpi/*` (librockit strings) [INFERENCE].
- Files and paths read/written:
  - writes `<-o path>/cap_out.pcm` (via `RK_MPI_AI_SaveFile`);
  - writes `/tmp/cap_aed_2ch.pcm` and `/tmp/cap_bcd_1ch.pcm` (algorithm dumps);
  - writes `/tmp/cap_out.pcm` (mode 1 raw capture);
  - writes `--aenc_file` (mode 1 encoded stream);
  - reads `--vqe_cfg` (passed to rockit). The device ships `/oem/usr/share/vqefiles/config_aivqe.json`, which configures aec/bf/fast_aec/aes/gsc/agc/anr/nlp… and is a likely candidate [INFERENCE].
- Network: none.
- Environment variables / config files: no `getenv` imports. Config file: `--vqe_cfg` (JSON).

## Relevance on this camera

It is not started at boot. A grep of the whole `downlaods/3/dump/` tree for `rk_mpi_ai_test` matches only the binary itself. It is not referenced by `RkLunch.sh`, `/etc/init.d/S??*`, `/oem/usr/etc/init.d/S10ntp` or `lp_app.sh`, and `lp_app` does not depend on it.

The camera does have a capture path (internal acodec, card 0), so running the test manually would really record from the microphone input if one is fitted. If `lp_app` already holds the AI device or ALSA PCM, `RK_MPI_AI_Enable` would probably fail or conflict [INFERENCE]. `--set_volume`/`--set_mute` change the AI gain and mute state for the running process [INFERENCE: may persist in ALSA mixer state]. It does not write to flash, reboot the device or touch GPIO.

## Evidence

- `readelf -d`: NEEDED `librockit.so`, `libstdc++.so.6`, `libgcc_s.so.1`, `libc.so.0`.
- `llvm-nm-14 -D` (imports): `RK_MPI_AI_{SetPubAttr,Enable,EnableChn,SetChnParam,EnableReSmp,SetVqeAttr,GetVqeAttr,EnableVqe,SetAedAttr,GetAedAttr,EnableAed,GetAedResult,SetBcdAttr,GetBcdAttr,EnableBcd,GetBcdResult,GetFrame,ReleaseFrame,SaveFile,SetVolume,GetVolume,SetMute,GetMute,SetTrackMode,GetTrackMode,Disable*}`, `RK_MPI_AENC_{CreateChn,GetStream,ReleaseStream,DestroyChn}`, `RK_MPI_SYS_{Init,Exit,Bind,UnBind}`, `RK_MPI_MB_{Handle2VirAddr,GetSize}`.
- Exported: `test_open_device_ai`, `test_init_mpi_ai`, `test_init_ai_vqe`, `test_init_ai_aed`, `test_init_ai_bcd`, `test_bcd_callback`, `sendDataThread`, `commandThread`, `test_ai_bind_aenc_loop`, `init_aenc_cfg`, `test_init_mpi_aenc`.
- `strings`: `/tmp/cap_aed_2ch.pcm`, `/tmp/cap_bcd_1ch.pcm`, `/tmp/cap_out.pcm`, `cap_out.pcm`, `baby cry callback successed`, `Invalid gap: %d, just supports 16ms or 10ms for AI VQE`, `need to resample %d -> %d`.
- Disassembly of `sendDataThread`:
  ```
  12cb8 movt r3,#1 ; "cap_out.pcm"
  12cd8 bl RK_MPI_AI_SaveFile
  12cdc ldr r3,[r4,#20] ; cmp r3,#16000 / #8000
  ```
- Option table recovered by a small interpreter over `llvm-objdump` output of `main` (0x11ec0–0x12b04): stores of `{type, short, long, value, help}` at a 32-byte stride from the `"help"` entry.
- Default literal pool at 0x122e0: `(16,0,4,1024,0,0,16,0,100,0)`, giving bit=16, period_count=4, period_size=1024, vqe_gap=16, volume=100.
- Card on the device: `dump/run/udev/data/c116:0` → `S:snd/by-path/platform-acodec-sound`.

## Open questions

- Which ALSA PCM name librockit uses when `--sound_card_name` is NULL (`hw:0,0` vs `default`) cannot be read from this binary [INFERENCE: librockit default].
- The exact meanings of the `loopback_mode` values are not printed anywhere in the binary.
- Whether a microphone is physically connected to the acodec on the Core One L camera board is unknown.
- Whether `lp_app` uses AI at all is unknown (`lp_app` is not in the dump).
