# `simple_vi_venc`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_venc` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14328` |
| sha256 | `2d92681aa42f72a536bc1a36c31637659eb951cbd874ce74860b00bbcb9b1cb8` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_vi_venc`), unmodified test tool |
| confidence | high |

## Summary

Builds a minimal camera-to-encoder pipeline. A VI channel (rkisp path) at a chosen resolution is bound to VENC channel 0, which encodes H.264, H.265 or MJPEG at 10 Mbit/s CBR, and the elementary stream is optionally written to a file. It is an SDK pipeline test tool and is not used by the camera.

## Usage

Printed for any unhandled option (getopt string `?::w:h:c:I:e:o:`):

```
usage example:
	%s -I 0 -w 1920 -h 1080 -o /tmp/venc.h264
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:150
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-e | --encode: encode type, Default:h264, Value:h264, h265, mjpeg
	-o: output path, Default:NULL
```

- `-w`, `-h`: VI and encoder size. Default 1920×1080.
- `-c <n>`: stop after more than `n` encoded frames. The help says the default is 150, but the actual default is −1 (run until SIGINT): `.data` holds `0xffffffff`.
- `-I <n>`: VI channel to use as the source (0 main path, 1 self path, 2 bypass). Default 0.
- `-e h264|h265|mjpeg`: codec. Sets `RK_CODEC_ID` 8 (`RK_VIDEO_ID_AVC`), 12 (`RK_VIDEO_ID_HEVC`) or 9 (`RK_VIDEO_ID_MJPEG`) [INFERENCE: enum names]. Default H.264. Any other value prints `ERROR: Invalid encoder type.` and exits.
- `-o <file>`: output file (`fopen64(path, "w")`). With no `-o`, nothing is written and only statistics are printed.

## How it works

1. Parses options and prints `#CodecName:`, `#Resolution:`, `#Output Path:`, `#CameraIdx:` and `#Frame Count to save:`. Opens `-o` if given, installs a SIGINT handler and calls `RK_MPI_SYS_Init`.
2. `vi_dev_init`, as in the other VI samples:
   - `RK_MPI_VI_GetDevAttr(0)`; if it returns `0xA0088007`, `RK_MPI_VI_SetDevAttr`
   - `RK_MPI_VI_GetDevIsEnable`; if not enabled, `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe(0, {0,0})`
3. `test_vi_init(chn, w, h)`: VI channel attr w×h, NV12, depth 2, 2 ISP buffers, DMABUF. Then `RK_MPI_VI_SetChnAttr(0, chn)` and `RK_MPI_VI_EnableChn(0, chn)`.
4. `test_venc_init(0, w, h, codec)` fills `VENC_CHN_ATTR_S`:
   - codec type
   - pixel format NV12
   - profile 100 (H.264 High)
   - pic and virtual width/height = w×h
   - stream buffer count 2, buffer size w×h×3/2, mirror none

   The RC part is **always** mode 1 (`VENC_RC_MODE_H264CBR` [INFERENCE: enum name]) with GOP 60 and bitrate 10240 kbit/s. This happens regardless of the codec chosen; there is no branch on the codec in this function. It then calls `RK_MPI_VENC_CreateChn(0)` and `RK_MPI_VENC_StartRecvFrame(0, {s32RecvPicNum = −1})`.

5. `RK_MPI_SYS_Bind({mod 8 (VI), dev 0, chn camid} → {mod 4 (VENC), dev 0, chn 0})`, printed as `====RK_MPI_SYS_Bind vi0 to venc0====`.
6. Thread `GetMediaBuffer0` loops:
   - `RK_MPI_VENC_GetStream(0, &stream, -1)`
   - `RK_MPI_MB_Handle2VirAddr`
   - `fwrite(data, 1, len, fp)` + `fflush` (when `-o` is set)
   - logs `chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus` (delay = `clock_gettime` − PTS)
   - `RK_MPI_VENC_ReleaseStream`
   - `usleep(10000)`

   It stops when the loop count exceeds `-c`.

7. On exit: `RK_MPI_SYS_UnBind`, `RK_MPI_VI_DisableChn(0, chn)`, `RK_MPI_VENC_StopRecvFrame(0)`, `RK_MPI_VENC_DestroyChn(0)` (its error message wrongly says `RK_MPI_VDEC_DestroyChn fail %x`), `RK_MPI_VI_DisableDev(0)`, `RK_MPI_SYS_Exit`.

The output is a raw Annex-B H.264/H.265 elementary stream, or concatenated JPEG frames for MJPEG [INFERENCE: format from codec type]. There is no container.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses rkisp video nodes (`/dev/video*`, `/dev/media%d`), the MPP encoder (via `librockchip_mpp`) and the rockit MPI devices (`/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`) [INFERENCE from library strings].
- Files and paths read/written: writes the `-o` file if given. The example uses `/tmp/venc.h264`.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** It is not referenced by any script in `downlaods/3/dump`, and `lp_app` does not depend on it. `lp_app` normally owns VI device 0, the rkisp main path and the hardware encoder. Running this tool at the same time would find the device already enabled and then try to set up and enable the same VI channel and create VENC channel 0, which may already exist in `lp_app`. This would probably fail with "exist/busy" errors or disturb the production stream [INFERENCE]. It has no persistent side effects apart from the optional output file.

## Evidence

- `readelf -p .rodata`: the usage lines, `H264`/`h264`/`h265`/`H265`/`mjpeg`/`MJPEG`, `ERROR: Invalid encoder type.`, `====RK_MPI_SYS_Bind vi0 to venc0====`, `chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus`, `RK_MPI_VDEC_DestroyChn fail %x`, `test_venc_init`, `vi_dev_init`, `GetMediaBuffer0`.
- `readelf -x .data`: `0x000232ec ffffffff 3f3a3a77 3a683a63 3a493a65 3a6f3a00`, which is frame count −1 followed by `?::w:h:c:I:e:o:`.
- Jump table at `0x11838` (base `'I'`): `I`→camid, `c`→frame count, `e`→codec strcmp chain, `h`, `o`, `w`; everything else → usage.
- Disassembly of `test_venc_init` (`0x113f4`):
  ```
  11438: mov r3,#1     ; str [fp,-60]   rc mode
  11440: mov r3,#10240 ; str [fp,-36]   bitrate
  11448: mov r3,#60    ; str [fp,-56]   gop
  11460: mov r3,#100   ; str [fp,-116]  profile
  11488: mov r3,#2     ; str [fp,-92]   stream buf cnt
  11498..114b4: w*h*3/2               buf size
  114cc: bl RK_MPI_VENC_CreateChn ; 114f8: bl RK_MPI_VENC_StartRecvFrame (recv num -1)
  ```
- Codec values: `119a0: mov r3,#8` (h264), `119e0: mov r3,#12` (h265), `11a20: mov r3,#9` (mjpeg).
- Bind: `11bc8: mov r3,#8` (VI) → `11be0: mov r3,#4` (VENC).

## Open questions

- Whether librockit or MPP accepts an H.264 CBR RC mode for an H.265 or MJPEG channel, or rejects or corrects it, cannot be determined statically [INFERENCE: the SDK source probably intended per-codec RC modes].
- Sensor and maximum resolution on this camera are not determinable from this binary.
