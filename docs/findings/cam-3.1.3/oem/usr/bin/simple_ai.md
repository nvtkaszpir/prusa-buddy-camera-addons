# `simple_ai`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_ai` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14264` |
| sha256 | `afa71f4b4974c4450e567a38bcd20a57d590efc6979db09694c3d36641de3f7a` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_ai`), unmodified test tool |
| confidence | high |

## Summary

Records from the microphone through the rockit audio-input (AI) module on ALSA card `hw:0,0` and writes raw 16-bit PCM to a file until it receives Ctrl-C. It is an SDK test tool; nothing on the camera calls it.

## Usage

The text below is printed for any unhandled option (getopt string `?::d:r:o:m:`):

```
usage example:
	%s [-r 8000] -o /tmp/ai.pcm
	-r: sample rate, Default:16000
	-o: output path, Default:"/tmp/ai.pcm"
```

- `-r <rate>`: sample rate for both the sound card and the AI channel. Default 16000. The same value is passed as the device rate and the channel rate, so the resampler branch is never taken.
- `-o <path>`: output file, opened with `fopen64(path, "w")`. Default `/tmp/ai.pcm`.
- `-d` and `-m` are in the getopt string but have no handler. They print the usage text and exit with status 0. This was confirmed in `main`, which compares only against `'o'` (111) and `'r'` (114).

At startup it echoes `#SampleRate:`, `#Frame Count:` (fixed at 1024) and `#Output Path:`.

## How it works

1. Parses options, opens the output file, installs a SIGINT handler (`signal %d`, sets quit flag) and calls `RK_MPI_SYS_Init`.
2. `open_device_ai(rate, rate, 1024)` fills `AIO_ATTR_S` (field names inferred from the rockit layout [INFERENCE]):
   - card name `"hw:0,0"`
   - sound card: 2 channels, rate, bit width 1 (16-bit)
   - `enSamplerate` = rate, `enBitwidth` = 1, sound mode 0 (mono)
   - `u32FrmNum` = 4, `u32PtNumPerFrm` = 1024, `u32ChnCnt` = 2

   It then calls `RK_MPI_AI_SetPubAttr(0)` → `RK_MPI_AI_Enable(0)` → `RK_MPI_AI_SetChnParam(0,0,{1,0})` → `RK_MPI_AI_EnableChn(0,0)`. If the device and channel rates differ it would call `RK_MPI_AI_EnableReSmp` (logged as `need to resample %d -> %d`), which never happens here.

3. `ai_set_other(100)` calls `RK_MPI_AI_SetVolume(0, 100)`, `RK_MPI_AI_SetTrackMode(0, 8)` and `RK_MPI_AI_GetTrackMode` (logged as `test info : get track mode = %d`). Track mode 8 is probably rockit's `AUDIO_TRACK_FRONT_LEFT` [INFERENCE].
4. A capture thread (`pthread_create`, function `GetMediaBuffer`) loops until the quit flag is set:
   - `RK_MPI_AI_GetFrame(0, 0, &frame, NULL, -1)`
   - `RK_MPI_MB_Handle2VirAddr`
   - logs `data = %p, len = %d`
   - `fwrite(data, len, 1, fp)` + `fflush`
   - `RK_MPI_AI_ReleaseFrame`

   The main thread prints `main initial finish` and polls the quit flag with `usleep(500000)`.

5. On SIGINT the thread closes the file. `main` calls `RK_MPI_AI_DisableChn(0,0)`, `RK_MPI_AI_Disable(0)` and `RK_MPI_SYS_Exit`.

**Dead VQE code:** a function `test_init_ai_vqe` is compiled in. It would load `/oem/usr/share/vqefiles/config_aivqe.json` with a 16 ms frame (`s32FrameSample = rate*16/1000`), checking `Invalid gap: %d, just supports 16ms or 10ms for AI VQE`, and would call `RK_MPI_AI_SetVqeAttr`, `RK_MPI_AI_GetVqeAttr` (with a memcmp check) and `RK_MPI_AI_EnableVqe`. Nothing calls it: the local call graph has no `bl 0x11168`. So the recorded audio is **not** processed by AEC/ANR/AGC.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses ALSA `hw:0,0` (`/dev/snd/pcmC0D0c`, `/dev/snd/controlC0` [INFERENCE from librockit format strings `/dev/snd/pcmC%uD%u%c`]) and the rockit MPI devices (`/dev/mpi/*`) [INFERENCE].
- Files and paths read/written: writes `-o` (default `/tmp/ai.pcm`). The string `/oem/usr/share/vqefiles/config_aivqe.json` is present but used only by the unreachable VQE function.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** `grep -r simple_ai downlaods/3/dump` finds no reference apart from the binary itself; the only `simple_a*` hits are `simple_ao`. `lp_app` does not depend on it.

Run by hand while `lp_app` is capturing audio, it would compete for AI device 0 / `hw:0,0`, and `RK_MPI_AI_Enable` or the ALSA open would probably fail [INFERENCE]. Side effects: it sets the AI (capture) volume to 100 and the track mode to 8 for device 0, which may persist for other users of the codec [INFERENCE]. It writes the output file, which grows without bound in `/tmp` (RAM) until stopped. No flash, GPIO or reboot side effects.

## Evidence

- `readelf -p .rodata simple_ai`: `hw:0,0`, `/oem/usr/share/vqefiles/config_aivqe.json`, `Invalid gap: %d, just supports 16ms or 10ms for AI VQE`, `need to resample %d -> %d`, `data = %p, len = %d`, `/tmp/ai.pcm`, usage lines, function-name strings `test_init_ai_vqe`, `ai_set_other`, `open_device_ai`, `GetMediaBuffer`.
- `strings simple_ai | grep '^?::'` → `?::d:r:o:m:`.
- Imports: `RK_MPI_AI_{SetPubAttr,Enable,SetChnParam,EnableChn,EnableReSmp,SetVolume,SetTrackMode,GetTrackMode,GetFrame,ReleaseFrame,SetVqeAttr,GetVqeAttr,EnableVqe,DisableChn,Disable}`, `RK_MPI_MB_Handle2VirAddr`, `pthread_create`, `fopen64`, `fwrite`.
- Disassembly:
  ```
  1182c: mov r3,#16000 ; 11834: mov r3,#1024 ; 1183c: ="/tmp/ai.pcm"
  1197c: bl open_device_ai(rate, rate, 1024)
  11468: mov r1,#8 ; bl RK_MPI_AI_SetTrackMode
  1105c: bl RK_MPI_AI_GetFrame (timeout -1) ... 110e8: bl fwrite ... 11110: bl RK_MPI_AI_ReleaseFrame
  119b0: usleep(0x7a120 = 500000)
  ```
- Local calls (`bl` to `.text`): `0x10d8c`, `0x10e68`, `0x11430` (`ai_set_other`), `0x117c8` (usage), `0x114c0` (`open_device_ai`). There is no call to `0x11168` (`test_init_ai_vqe`).

## Open questions

- The physical microphone and codec behind `hw:0,0` are not identifiable from the userland dump [INFERENCE: RV1106 internal acodec].
- With `u32ChnCnt=2` and mono sound mode, the output is probably interleaved mono 16-bit at the given rate. Whether rockit delivers one or two channels in each frame was not verified statically [INFERENCE].
- The exact enum meaning of `SetChnParam {1, 0}` (presumably user frame depth = 1, loopback off) and of track mode 8 comes from the SDK headers [INFERENCE].
