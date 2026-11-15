# `simple_ao`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_ao` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `10152` |
| sha256 | `bc925931635787af92edfef734b5c41eb0cd212276024e4a3e7ebe79ba3a6c20` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_ao`); vendor reuses it as the system's WAV/PCM prompt player |
| confidence | high |

## Summary

Plays a raw 16-bit PCM file to the speaker through the rockit audio-output (AO) module on ALSA card `hw:0,0`. You can set the sample rate, an optional AO resample rate, and the volume. Prusa's boot scripts use it to play voice prompts: the "upgrading" sound before entering recovery, and the "upgrade successful" sound after an update.

## Usage

The text below is printed when an unknown option is given (getopt string `?::d:r:i:t:s:v:`):

```
usage example:
	%s -r 16000 -s 16000 -i /tmp/16000.pcm
	-r: Resample rate, Default:16000
	-s: sample rate, Default:16000
	-i: input path, Default:"/tmp/16000.pcm"
	-v: set volume, Default:100
```

- `-i <path>`: input file. It is read as headerless PCM, signed 16-bit (`AUDIO_BIT_WIDTH_16`), in 1024-byte blocks. Default `/tmp/16000.pcm`.
- `-s <rate>`: sample rate of the file and of the AO device. Default 16000.
- `-r <rate>`: resample rate. If it differs from `-s`, the program calls `RK_MPI_AO_EnableReSmp(0, 0, rate)`. Default 16000.
- `-v <0..100>`: AO volume passed to `RK_MPI_AO_SetVolume`. Default 100.
- `-d` and `-t` appear in the getopt string but have no handler. Like any unknown option, they print the usage text and exit with status 0. This was confirmed from the jump table: the cases for `i`, `r`, `s` and `v` are handled, and everything else goes to the usage function.

The settings are echoed to stdout as `#SampleRate:`, `#s32ReSmpSampleRate:`, `#Frame Count:` (fixed at 1024), `#Input Path:` and `#Volume:`.

## How it works

1. Parses options with `getopt` and opens the input with `fopen64(path, "rb")`. On failure it prints `ERROR: open file: %s fail, exit`. It then installs a SIGINT handler (`signal(2, …)`) that prints `signal %d` and sets a quit flag.
2. Calls `RK_MPI_SYS_Init`.
3. `open_device_ao` fills an `AIO_ATTR_S` (field names inferred from the rockit layout [INFERENCE]):
   - card name `"hw:0,0"`, written with `sprintf("%s", "hw:0,0")` at offset 40
   - sound card: 2 channels, rate = `-s`, bit width 1 (16-bit)
   - `enSamplerate` = `-s`, `enBitwidth` = 1, `enSoundmode` = 0 (mono)
   - `u32FrmNum` = 4, `u32PtNumPerFrm` = 1024, `u32ChnCnt` = 2

   It then calls `RK_MPI_AO_SetPubAttr(0)` → `RK_MPI_AO_Enable(0)` → `RK_MPI_AO_SetChnParams(0,0)` → `RK_MPI_AO_EnableChn(0,0)`. If the resample rate differs from the sample rate, it prints `********RK_MPI_AO_EnableReSmp*********` and calls `RK_MPI_AO_EnableReSmp(0,0,resample)`.

4. `ao_set_other` calls `RK_MPI_AO_SetVolume(0, vol)`, then `RK_MPI_AO_GetVolume` (logged as `test info : get volume = %d`), then `RK_MPI_AO_SetTrackMode(0, 10)` and `RK_MPI_AO_GetTrackMode`. Track mode 10 is probably `AUDIO_TRACK_OUT_STEREO` in rockit's enum [INFERENCE].
5. Main loop, until EOF or SIGINT:
   - `calloc(1, 1024)` and `fread(buf, 1, 1024, fp)`
   - wrap the buffer in a media block with `RK_MPI_SYS_CreateMB`
   - `RK_MPI_AO_SendFrame(0, 0, &frame, -1)` (blocking); on error it logs `send frame fail, result = %d, TimeStamp = %lld, s32MilliSec = %d` and retries
   - `RK_MPI_MB_ReleaseMB`

   When `fread` returns 0, it prints `eof`, calls `RK_MPI_AO_WaitEos(0, 0, -1)` so the queued audio finishes playing, and leaves the loop.

6. Teardown: `fclose`, `free`, `RK_MPI_AO_DisableReSmp`, `RK_MPI_AO_DisableChn`, `RK_MPI_AO_Disable`, `RK_MPI_SYS_Exit`.

There is no WAV parsing. When the boot scripts pass a `.wav` file, its 44-byte RIFF header is played as two dozen samples, which is an inaudible or very short click. The shipped WAVs are `RIFF … WAVE audio, Microsoft PCM, 16 bit, mono 16000 Hz`, which match the defaults.

## Interfaces touched

- Device nodes / sysfs / procfs: none referenced directly in the binary. Through librockit it uses ALSA card `hw:0,0`; librockit contains `/dev/snd/pcmC%uD%u%c` and `/dev/snd/controlC%u`. It also uses the rockit/MPI kernel devices that librockit opens, such as `/dev/mpi/vsys` and `/dev/mpi/valloc` [INFERENCE: opened by `RK_MPI_SYS_Init`].
- Files and paths read/written: reads the `-i` file (default `/tmp/16000.pcm`). Called by the scripts with `/oem/usr/etc/upgrading.wav` and `/oem/usr/etc/upgrade_successful.wav`.
- Network: none.
- Environment variables / config files: none read by the binary. The volume passed by `upgrade_voice.sh` comes from `/userdata/xhr_config.ini` (`volume=`).

## Relevance on this camera

**Used at boot.** `downlaods/3/dump/oem/usr/bin/RkLunch.sh` calls it in two places:

- Line 78 starts `upgrade_voice.sh &`. If `/oem/usr/etc/upgrade_successful.wav` exists, that script runs `simple_ao -i /oem/usr/etc/upgrade_successful.wav -v $VOLUME` and then deletes the WAV. The volume comes from `/userdata/xhr_config.ini`, range 5..100, default 40.
- Line 87: if `/mnt/sdcard/cus_update_ota.tar` or `/mnt/sdcard/fac_update_ota.tar` exists, it runs `simple_ao -i /oem/usr/etc/upgrading.wav -v 50` and then `reboot recovery`.

Because `upgrade_voice.sh` runs in the background, it can overlap with the start of `lp_app`. If both open AO device 0 / `hw:0,0` at the same time, one of them may fail `RK_MPI_AO_Enable` or the ALSA open [INFERENCE]. Running it by hand while `lp_app` plays audio would compete for the same ALSA PCM.

Side effects: it only plays sound and changes the AO volume. It does not write to flash or change GPIO state. The speaker amplifier enable, if one exists, is not handled here [INFERENCE: handled by the codec driver or lp_app].

## Evidence

- `readelf -p .rodata simple_ao`: `hw:0,0`, `********RK_MPI_AO_EnableReSmp*********`, the usage lines above, `/tmp/16000.pcm`, `rb`, `eof`, `send frame fail, result = %d, TimeStamp = %lld, s32MilliSec = %d`.
- `strings simple_ao | grep '^?::'` → `?::d:r:i:t:s:v:`.
- `llvm-nm-14 -D --undefined-only`: `RK_MPI_AO_{Enable,EnableChn,EnableReSmp,SetPubAttr,SetChnParams,SetVolume,GetVolume,SetTrackMode,GetTrackMode,SendFrame,WaitEos,DisableReSmp,DisableChn,Disable}`, `RK_MPI_SYS_CreateMB`, `RK_MPI_MB_ReleaseMB`, `fopen64`, `fread`, `getopt`, `atoi`, `signal`.
- Disassembly, with PLT targets resolved from `.rel.plt`:
  ```
  112a4: mov r3,#16000 ; str [fp,-8]     (sample rate)
  112ac: mov r3,#16000 ; str [fp,-12]    (resample rate)
  112b4: mov r3,#1024  ; str [fp,-40]    (bytes per read)
  112c8: mov r3,#100   ; str [fp,-20]    (volume)
  11074: mov r3,#2 ; str [fp,-120]       (AIO attr: channels=2)
  110ac: mov r3,#4 ; str [fp,-92]        (u32FrmNum=4)
  10f8c: mov r1,#10 ; bl RK_MPI_AO_SetTrackMode
  11510: bl fread(buf,1,1024,fp) ... 115a8: bl RK_MPI_AO_SendFrame ... 1162c: bl RK_MPI_AO_WaitEos
  ```
- Jump table at `0x112e8` (base `'i'`): `i`→path, `r`→atoi→resample, `s`→atoi→rate, `v`→atoi→volume; all other entries go to `0x11388` (usage).
- `grep -rn simple_ao downlaods/3/dump` → `oem/usr/bin/RkLunch.sh:87`, `oem/usr/bin/upgrade_voice.sh:35`.
- `file oem/usr/etc/upgrading.wav` → `RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 16000 Hz`.
- The `.data` section also holds a table of rkaiq IQ section names (`awb_calib_para_v200`, `lut3d`, `bayerNr`, …) that the code never references. It is compiled in from rk_aiq headers [INFERENCE].

## Open questions

- The exact rockit enum names for `SetTrackMode(…, 10)` and for the meaning of `u32ChnCnt=2` with a mono sound mode are inferred from the public SDK headers [INFERENCE].
- Which physical codec and amplifier sit behind `hw:0,0` cannot be determined from the userland dump (there is no `/proc/asound` in it). On RV1106 it is usually the internal acodec [INFERENCE].
- Whether `upgrade_voice.sh` and `lp_app` actually collide on AO at boot depends on timing and on how lp_app opens audio. This was not determinable statically.
