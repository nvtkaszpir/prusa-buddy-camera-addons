# `sample_ai`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_ai` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14804` |
| sha256 | `9c2d67c0d0b17b397ddfab02f0beae51e864e090209056b5a2c64f57fab9cbbb` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi example `sample_ai` (built from the SDK `samples/example` tree; it contains the shared `SAMPLE_COMM_AI_*` helper functions) |
| confidence | high |

## Summary

This is a Rockchip SDK demo for audio capture. It opens the ALSA sound card through rockit's AI (audio input) module, reads PCM frames in a thread, and can append the raw PCM to `<dir>/ai_0.bin`. It is a developer/bring-up tool that ships with the SDK. Nothing on the camera starts it.

## Usage

The help text is printed when `argc <= 1` or when an unknown option is given. The program then exits with status 0. Verbatim:

```
usage example:
	%s -d default:CARD=rockchipes8388 -w 16bit -R 16000 -r 16000 -C 2 -c 2 -o /data/
	-d | --device_name: the sound name for open sound card, eg: default:CARD=rockchipes8388c Default(NULL)
	-w | --bit_width: the bit width of open sound card, Default:16bit, Value:8bit, 16bit, 24bit
	-R | --device_rate: the sample rate of open sound card, Default:16000
	-r | --out_rate: the sample rate of out data, Default:16000
	-C | --device_ch: the number of sound card channels, Default:2
	-c | --out_ch: the channels of out data, Default:2
	-l | --loop_count: loop running count, Default -1
	-o | --output_path: encode save file path, Default /data/
```

Option parsing uses plain `getopt` with the string `"?::d:w:R:r:C:c:l:o:"`. **Only the short options work.** The binary does not import `getopt_long`, so the `--long` names in the help do nothing. The actual defaults were taken from `main` (`0x1117c`); several differ from the help text:

| opt | meaning | actual default (from code) |
|---|---|---|
| `-d` | ALSA device/card name, copied into `AIO_ATTR_S.u8CardName` | NULL (empty name, so rockit picks its default card) |
| `-w` | sound-card bit width `8bit`/`16bit`/`24bit`, mapped to 0/1/2 | 1 (16-bit) |
| `-R` | sound-card (hardware) sample rate | 16000 |
| `-r` | output sample rate (`enSamplerate`) | **8000** (help says 16000) |
| `-C` | sound-card channel count | 2 |
| `-c` | output channels; 1 means mono and 2 means stereo. Any other value prints `channel = %d not support` and exits | 2 |
| `-l` | number of frames to capture before stopping; -1 means forever | -1 |
| `-o` | output **directory**; the file is `/<dir>/ai_0.bin` | **NULL, so no file is written** (help says `/data/`) |

## How it works

1. `main` fills a 168-byte context with these fields: `u32FrmNum = 4`, `u32PtNumPerFrm = 1024`, `AI dev 0 / chn 0`, sound-card channels/rate/bit width, output rate/bit width, and sound mode derived from `-c`. It installs a `SIGINT` handler (`signal(2, …)`, `"signal %d\n"`), then prints `#Device`, `#SampleRate`, `#Channel Count`, `#Loop Count` and `#Output Path`.
2. It calls `RK_MPI_SYS_Init`.
3. `SAMPLE_COMM_AI_CreateChn` (`0x11828`) calls `RK_MPI_AI_SetPubAttr(dev 0, attr)`, `RK_MPI_AI_Enable(0)`, `RK_MPI_AI_EnableChn(0, 0)` and `RK_MPI_AI_EnableReSmp(0, 0, ctx+16)` in that order. The resample-rate field at ctx+16 is never written by `main`, so it remains 0 from the `memset` [INFERENCE: rockit treats 0 as "no explicit rate" / output rate].
4. A thread `ai_get_stream` is started with `pthread_create`. If an output path was given, it builds the file name with `snprintf("/%s/ai_%d.bin", path, chn)` and opens it with `fopen64(…,"wb")`. It then loops on `RK_MPI_AI_GetFrame` (timeout -1) and `RK_MPI_MB_Handle2VirAddr`, does `fwrite` + `fflush` of the raw PCM, and calls `RK_MPI_AI_ReleaseFrame`. Each frame is logged with `RK_LOG("chn:%d, loopCount:%d wd:%d")`. When `loopCount` reaches `-l`, it sets the quit flag.
5. `main` polls the quit flag with `usleep(500000)` and prints `main exit!`. It then runs `pthread_join`, then `SAMPLE_COMM_AI_DestroyChn` (`RK_MPI_AI_DisableReSmp`, `RK_MPI_AI_DisableChn`, `RK_MPI_AI_Disable`), then `RK_MPI_SYS_Exit`.

The output is headerless interleaved PCM at the output rate, bit width and channel count.

The many ISP-looking strings in `.rodata` (`awb_calib_para_v200`, `bayerNr`, `list_ynr_v2` …) are static tables from an rkaiq header that the SDK sample includes. The program never calls rkaiq.

## Interfaces touched

- Device nodes / sysfs / procfs: none are referenced directly by the binary. Through librockit (its strings include `/dev/snd/pcmC%uD%u%c`, `/dev/snd/controlC%u` and `/dev/mpi/*`) it opens the ALSA capture device. On this camera that is card 0 `platform-acodec-sound` (`/dev/snd/pcmC0D0c`, the SoC's internal audio codec, per `run/udev/data/c116:0` and `downlaods/2/find.log`) [INFERENCE: card selection when `-d` is empty].
- Files and paths read/written: `/<-o dir>/ai_0.bin` (written, only with `-o`).
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- No startup script launches it: a grep for `sample_ai` across `downlaods/3/dump/` finds only an unrelated `sample_aie_module` string inside `rkisp_demo`. Neither `RkLunch.sh` nor any `init.d` script references it.
- `lp_app` does not depend on it. However, `lp_app` imports the same AI API (`RK_MPI_AI_SetPubAttr/Enable/EnableChn/EnableVqe…`), so it captures from the same codec. Running `sample_ai` while `lp_app` holds AI device 0 would likely fail in `RK_MPI_AI_Enable`/`SetPubAttr` or in the ALSA open [INFERENCE].
- Side effects: it writes a file only if `-o` is given. It does not touch GPIO/PWM/LEDs, flash or reboot.

## Evidence

```
$ readelf -d sample_ai | grep NEEDED  -> librockit.so librockchip_mpp.so.1 librkaiq.so libc.so.0
$ llvm-nm-14 -D --undefined-only sample_ai | grep RK_MPI
RK_MPI_AI_Disable RK_MPI_AI_DisableChn RK_MPI_AI_DisableReSmp RK_MPI_AI_Enable RK_MPI_AI_EnableChn
RK_MPI_AI_EnableReSmp RK_MPI_AI_GetFrame RK_MPI_AI_ReleaseFrame RK_MPI_AI_SetPubAttr
RK_MPI_MB_Handle2VirAddr RK_MPI_SYS_Exit RK_MPI_SYS_Init   (+ getopt, fopen64, fwrite, pthread_create)
$ strings -t x sample_ai | grep -e '?::' -e ai_
   32d0 ?::d:w:R:r:C:c:l:o:
   1dbc /%s/ai_%d.bin
```
Defaults in `main` (PLT calls and string refs were annotated by mapping `.rel.plt` and `movw/movt` pairs):
```
11190: mov r3,#2      ; device channels
11198: mov r3,#16000  ; device rate
111a0: mov r3,#1      ; bit width = 16bit
111a8: mov r3,#8000   ; out rate
111c0: mov r3,#4      ; u32FrmNum
111c8: mov r3,#1024   ; u32PtNumPerFrm
111d0: mvn r3,#0      ; loop count -1
111d8/111e0: 0        ; card name / output path = NULL
111ec: cmp argc,#1 ; ble -> usage, return 0
```
Switch on `opt-'C'`: `C`→dev ch, `R`→dev rate, `c`→out ch, `d`→card name, `l`→loop, `o`→out path, `r`→out rate, `w`→strcmp 8bit/16bit/24bit.
Thread (`0x10ed4`): `if (ctx->path) snprintf("/%s/ai_%d.bin") ; fopen64 "wb"` … `RK_MPI_AI_GetFrame` → `fwrite(…)` → `fflush`.
Device evidence: `downlaods/3/dump/run/udev/data/c116:0` = `S:snd/by-path/platform-acodec-sound`; `find.log` lists only `/dev/snd/pcmC0D0c` and `pcmC0D0p`.

## Open questions

- The ALSA card rockit opens when `-d` is not given (empty `u8CardName`) is decided inside librockit and was not traced [INFERENCE: `default`, i.e. card 0 acodec].
- The usage example's card name `rockchipes8388` (an ES8388 codec board) does not exist on this camera. Its only card is `acodec`.
- The exact behaviour of `RK_MPI_AI_EnableReSmp` with a 0 rate argument is unknown.
