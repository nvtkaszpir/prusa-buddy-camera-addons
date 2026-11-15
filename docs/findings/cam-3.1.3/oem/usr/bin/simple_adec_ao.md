# `simple_adec_ao`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_adec_ao` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14268` |
| sha256 | `8a8123bbabc0023ebe709a8fe3b444805de6963cc25d9e6fa139b9366f5784a3` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_adec_ao`), unmodified test tool |
| confidence | high |

## Summary

Reads a raw G.711 A-law, G.711 µ-law or G.726 bitstream from a file, decodes it with the rockit ADEC module, and plays it through the AO module on ALSA `hw:0,0`, with ADEC bound to AO. It is the playback counterpart of `simple_ai_aenc` and is not used by the camera.

## Usage

Printed for any unhandled option (getopt string `?::d:r:i:t:`, stored in `.data`):

```
usage example:
	%s -r 8000 -t g726 -i /tmp/aenc.g726
	-r: sample rate, Default:16000
	-t: --decode: decode type, Default:g726, Value:g711a, g711u, g726
	-i: input path, Default:"/tmp/aenc.g726"
```

- `-r <rate>`: sample rate for ADEC and AO. Default 16000.
- `-t g711a|g711u|g726`: decoder. Codec IDs `0x40000002`, `0x40000003`, `0x40000008`. Default `g726` (`.data` initialiser `0x40000008`). Any other value prints `ERROR: Invalid encoder type.` and exits.
- `-i <path>`: input file (`fopen64(path, "rb")`). Default `/tmp/aenc.g726`.
- `-d` is in the getopt string but unhandled: it prints usage and exits. `main` compares only `r` (114), `t` (116) and `i` (105).

## How it works

1. Parses options, opens the input, installs a SIGINT handler and calls `RK_MPI_SYS_Init`.
2. `open_device_ao(rate, 1024)` builds `AIO_ATTR_S` (field names inferred [INFERENCE]):
   - card `"hw:0,0"`, sound card 1 channel / rate / 16-bit
   - `enSamplerate` = rate, 16-bit, mono, 4 frames × 1024, `u32ChnCnt` = 2

   Calls: `RK_MPI_AO_SetPubAttr(0)` → `RK_MPI_AO_Enable(0)` → `RK_MPI_AO_SetChnParams(0,0)` → `RK_MPI_AO_EnableChn(0,0)` → `RK_MPI_AO_EnableReSmp(0,0,rate)` (called unconditionally) → `ao_set_other(100)`. That last step runs `RK_MPI_AO_SetVolume(0,100)`, `RK_MPI_AO_GetVolume`, `RK_MPI_AO_SetTrackMode(0,10)` and `RK_MPI_AO_GetTrackMode`.

3. `init_mpi_adec(rate)` fills `ADEC_CHN_ATTR_S`: codec ID, mode `1`, buffer count 4, buffer size 51200, codec attr {codec ID, 1 channel, rate, `4`}. Then `RK_MPI_ADEC_CreateChn(0, &attr)`; on failure it logs `create adec chn %d err:0x%x`.
4. `RK_MPI_SYS_Bind({mod 13, 0, 0} → {mod 11, 0, 0})`, i.e. ADEC[0] → AO[0] [INFERENCE: 13 = `RK_ID_ADEC`, 11 = `RK_ID_AO`]. The error string is a leftover copy-paste: `Bind AI[0] to AENC[0] failed! ret=%d`.
5. Feed loop:
   - `calloc(1,1024)` and `fread(buf,1,1024,fp)`
   - wrap with `RK_MPI_SYS_CreateMB`; the free callback is a local function that calls `free`
   - `RK_MPI_ADEC_SendStream(0, &stream, 1)` (blocking); on failure it logs `fail to send adec stream.`
   - `RK_MPI_MB_ReleaseMB`; a sequence counter and PTS are incremented

   At EOF it logs `read eos packet, now send eos packet!`, calls `RK_MPI_ADEC_SendEndOfStream`, and leaves the loop. SIGINT also stops it.

6. Teardown runs immediately afterwards: `fclose`, `RK_MPI_SYS_UnBind`, `RK_MPI_AO_DisableReSmp`, `RK_MPI_AO_DisableChn`, `RK_MPI_AO_Disable`, `RK_MPI_ADEC_DestroyChn`, `RK_MPI_SYS_Exit`. Nothing like `RK_MPI_AO_WaitEos` is called, so the end of the clip may be cut off [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses ALSA `hw:0,0` playback and the rockit MPI devices [INFERENCE].
- Files and paths read/written: reads `-i` (default `/tmp/aenc.g726`).
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** It is not referenced by any script in `downlaods/3/dump`, and `lp_app` does not depend on it. Running it alongside `lp_app` or `simple_ao` would contend for AO device 0 / `hw:0,0` [INFERENCE]. It sets the AO volume to 100 and the track mode to 10. No flash, GPIO or reboot side effects.

## Evidence

- `readelf -p .rodata`: `hw:0,0`, `test info : get volume = %d`, `create adec chn %d err:0x%x`, the usage lines, `/tmp/aenc.g726`, `g726`, `g711a`, `g711u`, `rb`, `Bind AI[0] to AENC[0] failed! ret=%d`, `read eos packet, now send eos packet!`, `fail to send adec stream.`, function names `ao_set_other`, `open_device_ao`, `init_mpi_adec`.
- `readelf -x .data`: `0x000232e4 08000040 3f3a3a64 3a723a69 3a743a00`, which is default codec `0x40000008` followed by `?::d:r:i:t:`.
- Disassembly:
  ```
  114f4: mov r3,#16000 ; 114fc: mov r3,#1024
  110cc: mov r1,#10 ; bl RK_MPI_AO_SetTrackMode
  112dc: bl RK_MPI_AO_EnableReSmp(0,0,rate)
  113cc: mov r3,#4 ; 113d4: mov r3,#51200 ; bl RK_MPI_ADEC_CreateChn
  1176c: mov r3,#13 (src) ; 11784: mov r3,#11 (dst) ; bl RK_MPI_SYS_Bind
  11854: bl fread(buf,1,1024,fp) ... 11950: bl RK_MPI_SYS_CreateMB ... 11964: bl RK_MPI_ADEC_SendStream(…,1)
  118b8: bl RK_MPI_ADEC_SendEndOfStream
  ```
- Imports: `RK_MPI_ADEC_{CreateChn,SendStream,SendEndOfStream,DestroyChn}`, `RK_MPI_AO_*` (no `WaitEos`), `RK_MPI_SYS_{Bind,UnBind,CreateMB}`, `RK_MPI_MB_ReleaseMB`.

## Open questions

- The meanings of ADEC attribute fields `mode = 1` (probably `ADEC_MODE_STREAM`) and the trailing `4` in the codec attr are inferred from the SDK struct layout [INFERENCE].
- Whether the missing `WaitEos` truncates the tail in practice depends on librockit's teardown behaviour. This was not determinable statically.
