# `simple_ai_aenc`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_ai_aenc` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14272` |
| sha256 | `f88ea6ea7044966828cfba6608201eba6324e412cc6a6a4e46787da02f66bd2a` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_ai_aenc`), unmodified test tool |
| confidence | high |

## Summary

Captures audio from ALSA `hw:0,0` with the rockit AI module, encodes it with the rockit AENC module as G.711 A-law, G.711 µ-law or G.726, and writes the raw encoded bitstream to a file until Ctrl-C. It is an SDK test tool; nothing on the camera calls it.

## Usage

Printed for any unhandled option (getopt string `?::r:o:t:`, stored in `.data`):

```
usage example:
	%s [-r 8000] [-t g726] -o /tmp/aenc.g726
	-r: sample rate, Default:16000
	-t: --encode: encode type, Default:g726, Value:g711a, g711u, g726
	-o: output path, Default:"/tmp/aenc.g726"
```

- `-r <rate>`: capture and encode sample rate. Default 16000.
- `-t g711a|g711u|g726`: codec. It sets the global codec ID to `0x40000002`, `0x40000003` or `0x40000008`, which are rockit `RK_AUDIO_ID_PCM_ALAW`, `RK_AUDIO_ID_PCM_MULAW` and `RK_AUDIO_ID_ADPCM_G726` [INFERENCE: enum names; the values are from the binary]. Default `g726`: `.data` initialises the codec ID to `0x40000008`. Any other string prints `ERROR: Invalid encoder type.` and exits.
- `-o <path>`: output file (`fopen64(path, "w")`). Default `/tmp/aenc.g726`.

`--encode` appears only in the help text. There is no `getopt_long`, so the long form is not accepted.

At startup it prints `#SampleRate:`, `#Frame Count:` (1024), `#CodecName:` and `#Output Path:`.

## How it works

1. Parses options, opens the output, installs a SIGINT handler and calls `RK_MPI_SYS_Init`.
2. `open_device_ai(rate, rate, 1024)` is the same as in `simple_ai`:
   - `AIO_ATTR_S` with card `"hw:0,0"`, sound card 2 ch / rate / 16-bit
   - `enSamplerate` = rate, 16-bit, mono, 4 frames × 1024 samples, `u32ChnCnt` = 2

   Calls: `RK_MPI_AI_SetPubAttr(0)` → `RK_MPI_AI_Enable(0)` → `RK_MPI_AI_SetChnParam(0,0,{1,0})` → `RK_MPI_AI_EnableChn(0,0)`. The resample branch is unused. Then `ai_set_other(100)`: `RK_MPI_AI_SetVolume(0,100)`, `RK_MPI_AI_SetTrackMode(0,8)`, `RK_MPI_AI_GetTrackMode`.

3. `init_mpi_aenc(rate)` prints `codecId=%d` and fills `AENC_CHN_ATTR_S`: codec ID, buffer count 4, codec attr {codec ID, 1 channel, `1`, sample rate}. The `1` is probably bit width 16 [INFERENCE]. It then calls `RK_MPI_AENC_CreateChn(0, &attr)`; on failure it logs `create aenc chn %d err:0x%x`.
4. `RK_MPI_SYS_Bind({mod 10, dev 0, chn 0} → {mod 12, dev 0, chn 0})`, i.e. AI[0] → AENC[0]. Mod 10/12 = `RK_ID_AI`/`RK_ID_AENC` [INFERENCE: enum names]. On failure it prints `Bind AI[0] to AENC[0] failed! ret=%d`.
5. Main loop, same thread:
   - `RK_MPI_AENC_GetStream(0, &stream, -1)`
   - `RK_MPI_MB_Handle2VirAddr`
   - logs `get frame data = %p, size = %d, timeStamp = %lld`
   - `fwrite` + `fflush` to the output
   - `RK_MPI_AENC_ReleaseStream`

   A stream with length ≤ 0 is treated as EOS (`get eos stream.`) and ends the loop. A failed `GetStream` logs `fail to get aenc frame.`. SIGINT also ends it.

6. Teardown: `RK_MPI_SYS_UnBind`, `RK_MPI_AI_DisableChn`, `RK_MPI_AI_Disable`, `RK_MPI_AENC_DestroyChn`, `RK_MPI_SYS_Exit`.

The output is a bare codec bitstream with no WAV or AU header. librockit carries the software codecs (`RTAudioG711EncDec`, `RTAudioG726EncDec` strings). Like `simple_ai`, the binary contains an `init_ai_vqe` function (VQE from `/oem/usr/share/vqefiles/config_aivqe.json`, 16 ms frames), but nothing calls it: there is no `bl 0x110b8`.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses ALSA `hw:0,0` capture and the rockit MPI devices [INFERENCE].
- Files and paths read/written: writes `-o` (default `/tmp/aenc.g726`). The string `/oem/usr/share/vqefiles/config_aivqe.json` is present but used only by unreachable code.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** There are no references anywhere in `downlaods/3/dump` other than the binary itself, and `lp_app` does not depend on it. While `lp_app` owns the microphone, AI device 0 / `hw:0,0` would be contended and setup would probably fail [INFERENCE]. Running it sets the AI volume to 100 and the track mode to 8. It writes a file that keeps growing until stopped. No flash, GPIO or reboot side effects.

## Evidence

- `readelf -p .rodata`: `hw:0,0`, `codecId=%d`, `create aenc chn %d err:0x%x`, the usage lines, `/tmp/aenc.g726`, `g726`, `g711a`, `g711u`, `Bind AI[0] to AENC[0] failed! ret=%d`, `get frame data = %p, size = %d, timeStamp = %lld`, `fail to get aenc frame.`, `get eos stream.`, `/oem/usr/share/vqefiles/config_aivqe.json`.
- `readelf -x .data`: `0x000232ec 08000040 3f3a3a72 3a6f3a74 3a00`, which is default codec `0x40000008` followed by `?::r:o:t:`.
- Disassembly:
  ```
  11890: mov r3,#16000 ; 11898: mov r3,#1024 ; ="/tmp/aenc.g726" ; ="g726"
  1194c: mov r2,#0x40000002  (g711a)   11994: mov r2,#0x40000003 (g711u)   119dc: mov r2,#0x40000008 (g726)
  117b4: mov r3,#4 ; bl RK_MPI_AENC_CreateChn
  11b0c: mov r3,#10 (src mod) ... 11b24: mov r3,#12 (dst mod) ; bl RK_MPI_SYS_Bind
  11ba8: bl RK_MPI_AENC_GetStream(0,&s,-1) ... 11c70: bl fwrite ... 11c94: bl RK_MPI_AENC_ReleaseStream
  ```
- Imports include `RK_MPI_AENC_{CreateChn,GetStream,ReleaseStream,DestroyChn}`, `RK_MPI_AI_*`, `RK_MPI_SYS_{Bind,UnBind}`.
- `strings librockit.so`: `RTAudioG711EncDec`, `RTAudioG726EncDec`.

## Open questions

- The G.726 bitrate (16/24/32/40 kbit/s) is not set by this binary, so it is whatever librockit defaults to [INFERENCE: probably 32 kbit/s].
- The meaning of the AENC attribute field set to `1` (between channels and sample rate) is inferred as bit width [INFERENCE].
- Sound card identity behind `hw:0,0` is unknown from the dump.
