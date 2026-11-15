# `sample_ai_aenc`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_ai_aenc` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `20144` |
| sha256 | `9a9810a394545cd04708578f375686379de572a293e25943cd12afdf13d32fd5` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi example `sample_ai_aenc` (contains SDK `SAMPLE_COMM_AI_*`, `SAMPLE_COMM_AENC_*`, `SAMPLE_COMM_Bind/UnBind` helpers) |
| confidence | high |

## Summary

This is a Rockchip SDK demo that captures audio and encodes it. It captures from the sound card via rockit AI, binds AI → AENC (audio encoder), and writes the encoded stream to `<dir>/aenc_0.bin`. It is a developer test tool. Nothing on the camera starts it.

## Usage

The help text is printed when `argc <= 1` or when an unknown option is given (exit status 0). Verbatim:

```
usage example:
	%s -d default:CARD=rockchipes8388 -w 16bit -R 16000 -r 16000 -C 2 -c 2 -e mp2 -o /data/
	-d | --device_name: the sound name for open sound card, eg: default:CARD=rockchipes8388c Default(NULL)
	-w | --bit_width: the bit width of open sound card, Default:16bit, Value:8bit, 16bit, 24bit
	-R | --device_rate: the sample rate of open sound card, Default:16000
	-r | --out_rate: the sample rate of out data, Default:16000
	-C | --device_ch: the number of sound card channels, Default:2
	-c | --out_ch: the channels of out data, Default:2
	-e | --encode: encode type, Defaule:mp3, Value:mp3, mp2, g711a, g711u, g726
	-l | --loop_count: loop running count, Default -1
	-o | --output_path: encode save file path, Default /data/
```

Parsing uses `getopt` with `"?::d:w:R:r:C:c:e:l:o:"`. Only the short options work because there is no `getopt_long`. Actual defaults, taken from `main` at `0x11508`:

| opt | meaning | actual default |
|---|---|---|
| `-d` | ALSA card name, copied into `AIO_ATTR_S.u8CardName` | NULL |
| `-w` | bit width `8bit`/`16bit`/`24bit`, mapped to 0/1/2 | 16-bit |
| `-R` | sound-card sample rate | 16000 |
| `-r` | output/encode sample rate | **8000** (help says 16000) |
| `-C` | sound-card channels | 2 |
| `-c` | output/encode channels (1 or 2 only) | 2 |
| `-e` | codec, see the table below | **`mp2`** (global initialised to `0x7f000006`; the help says mp3) |
| `-l` | number of encoded frames before stopping | -1 (forever) |
| `-o` | output directory; the file is `/<dir>/aenc_0.bin` | NULL, so **no file** |

Mapping from `-e` to rockit `RK_CODEC_ID_E` values, as stored by the code:

| `-e` | id written |
|---|---|
| `mp2` | `0x7f000006` |
| `mp3` | `0x4000001b` |
| `g726` | `0x40000008` |
| `g711a` | `0x40000002` |
| `g711u` | `0x40000003` |

For id `0x4000001b` (the `mp3` choice), the writer thread prepends a **7-byte ADTS header** to every packet (sync bytes `0xFF 0xF1`, built using the AAC sampling-frequency table 96000/88200/64000/48000… at `.data+0x234`). So that id is really treated as **AAC**, and the `mp3` label is wrong [INFERENCE: `0x4000001b` = `RK_AUDIO_ID_AAC` in rockit].

## How it works

1. Defaults and options are handled as above. A `SIGINT` handler is installed. The program prints `#Device`, `#SampleRate`, `#Channel Count`, `#Loop Count`, `#Output Path` and `#code_type: %d`, then calls `RK_MPI_SYS_Init`.
2. AI setup is identical to `sample_ai`: `RK_MPI_AI_SetPubAttr` → `RK_MPI_AI_Enable` → `RK_MPI_AI_EnableChn` → `RK_MPI_AI_EnableReSmp`, on dev 0 / chn 0, with 4 frames of 1024 samples.
3. `SAMPLE_COMM_AENC_CreateChn` calls `RK_MPI_AENC_CreateChn(0, attr)`. The attributes are: codec type from `-e`, buffer count 4, and output bit width, channels and sample rate.
4. `SAMPLE_COMM_Bind` calls `RK_MPI_SYS_Bind({mod 10 = AI, dev 0, chn 0} → {mod 12 = AENC, dev 0, chn 0})`.
5. The thread `aenc_get_stream` runs `fopen64("/%s/aenc_%d.bin","wb")` if `-o` was given. It then loops `RK_MPI_AENC_GetStream` → `RK_MPI_MB_Handle2VirAddr` → `[ADTS header if id==0x4000001b]` → `fwrite` → `fflush` → `RK_MPI_AENC_ReleaseStream`, logging `chn:%d, loopCount:%d wd:%d`. It stops after `-l` packets or on Ctrl-C.
6. Teardown: `SAMPLE_COMM_UnBind` (`RK_MPI_SYS_UnBind`), `RK_MPI_AENC_DestroyChn`, AI disable, `RK_MPI_SYS_Exit`.

Encoder availability: the bundled `librockit.so` contains only `RTAudioG711EncDec` and `RTAudioG726EncDec`, plus the `unsupport rockit codec id: %s` string. This binary does not call `RK_MPI_AENC_RegisterEncoder`. The default `mp2` and the `mp3`/AAC choices therefore probably fail in `RK_MPI_AENC_CreateChn` (`"RK_MPI_AENC_CreateChn failed %x"`). Only `g711a`, `g711u` and `g726` are expected to work [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none are referenced directly. Through librockit it uses ALSA capture (`/dev/snd/pcmC%uD%u%c`, on this camera card 0 `platform-acodec-sound`, `/dev/snd/pcmC0D0c`) and the rockit kernel MPI nodes (`/dev/mpi/vsys`, `/dev/mpi/valloc` …) [INFERENCE from librockit strings].
- Files and paths read/written: `/<-o dir>/aenc_0.bin` (written, only with `-o`).
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- It is not started at boot: there are no references in `RkLunch.sh`, `/etc/init.d/*`, `/oem/usr/etc/init.d/*` or anywhere else in the dump.
- `lp_app` does not depend on it. `lp_app` imports the AI API itself, so running this while `lp_app` holds AI dev 0 / the capture PCM would probably fail or interfere [INFERENCE].
- There are no hardware side effects apart from audio capture. It writes only the optional output file.

## Evidence

```
$ strings -t x sample_ai_aenc | grep -e '?::' -e aenc_
   4358 ?::d:w:R:r:C:c:e:l:o:
   ... /%s/aenc_%d.bin
$ readelf -x .data sample_ai_aenc | grep 0x000242ec
  0x000242ec 0600007f 00770100 00000000 88580100   <- default codec 0x7f000006, then AAC rate table
```
Option handler (`-e`):
```
117f8: "mp2"  -> movw r3,#6 ; movt r3,#0x7f00 ; str -> 0x7f000006
11838: "mp3"  -> mov r2,#0x4000001b
11874: "g726" -> mov r2,#0x40000008
118b0: "g711a"-> mov r2,#0x40000002
118ec: "g711u"-> mov r2,#0x40000003
```
Writer thread:
```
11360: cmp r3,#0x4000001b ; bne skip
1138c: bl 0x11098      ; builds header: strb 0xff, strb 0xf1 (mvn #14) ...
113a0: fwrite(hdr,1,7,fp)
113b8: fwrite(data,1,len,fp) ; fflush
```
Bind: `11b64: mov r3,#10` (src mod AI), `11b84: mov r3,#12` (dst mod AENC), then `bl 0x120fc` → `RK_MPI_SYS_Bind`.
librockit: `strings librockit.so | grep -i -E 'g711|g726|mp3|mp2|aac'` shows only `g711a g711u g726 RTAudioG711EncDec RTAudioG726EncDec` (and one `aac` token).

## Open questions

- Whether this rockit build can encode MP2 or AAC without an externally registered encoder was not verified. No encoder library for them exists in `oem/usr/lib`.
- The exact `RK_CODEC_ID_E` names for `0x7f000006` and `0x4000001b` are inferred. The rockit header is not in the dump.
- The card name used when `-d` is omitted is decided inside librockit [INFERENCE: default card 0].
