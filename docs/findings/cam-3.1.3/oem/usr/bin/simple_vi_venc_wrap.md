# `simple_vi_venc_wrap`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_venc_wrap` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14332` |
| sha256 | `20c10847625ce06cdbcd9fd0733c76ffed95fa29814304b160a911c7d61bce72` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_vi_venc_wrap`), unmodified test tool |
| confidence | high (flow, options), medium (exact struct field names) |

## Summary

A VI → VENC test pipeline that exercises the RV1106 **wrap (ring-buffer, low-latency) mode**. In this mode the VI/ISP channel does not write whole frames to DDR. It writes into a small circular buffer only `wrap_line` lines high, and the hardware encoder reads those lines as they are produced. The tool also exercises VENC "de-breath" and the reference-buffer-share attribute (left disabled). It prints per-frame statistics and is not used by the camera.

## Usage

Printed for any unhandled option. Options are parsed with `getopt_long`; short string `?::d:n:w:h:W:H:c:I:o:`.

```
usage example:
	%s -I 0 -w 1920 -h 1080 -W 2560 -H 1440 -o 1
	-w | --width: VI width, Default:2560
	-h | --height: VI height, Default:1440
	-W | --maxWidth: sensor output resolution max width, Default:2560
	-H | --maxHeight: sensor output resolution max height, Default:1440
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-o: output path, Default:0  0 or 1 /data/test_0.yuv
```

Long-option table, decoded from `.rodata` at `0x12a54` as {name, has_arg, val}, with the behaviour of each handler in the jump table at `0x11d08`:

| option | val | effect | default |
|---|---|---|---|
| `-w`, `--width` | `w` | VI/encode width | **1920** (help says 2560) |
| `-h`, `--height` | `h` | VI/encode height | **1080** (help says 1440) |
| `-W`, `--maxWidth` | `W` | sensor max width (VI max size, VENC max pic width) | 2560 |
| `-H`, `--maxHeight` | `H` | sensor max height | 1440 |
| `-I`, `--camid` | `I` | VI channel number | 0 |
| `-o`, `--output_path` | `o` | `atoi`: 0/1 enable flag for `RK_MPI_VI_ChnSaveFile`; not a path | 0 |
| `--wrap` | `r` | wrap-mode enable (`atoi`) | **1** |
| `--wrap_line` | `L` | wrap buffer height in lines; must be 128 ≤ L ≤ height | 0 (**invalid**, see below) |
| `--codec` | `C` | numeric `RK_CODEC_ID` for VENC (8 = H.264, 12 = H.265, 9 = MJPEG [INFERENCE: enum]) | **12** (H.265) |
| `--de_breath` | `D` | if ≠ 0, enable VENC de-breath with this strength | 0 (off) |
| `--loop_count` | `l` | frames to encode / stop count | −1 (infinite) |
| `--aiq`, `--pixel_format`, `--device_name`, `--camera_num`, `-d`, `-n`, `-c`, `--help` | `a`,`f`,`d`,`n`,`c`,`?` | no handler, so usage is printed and the program exits | — |

`--wrap`, `--wrap_line`, `--codec`, `--de_breath` and `--loop_count` exist only as long options; their letters are not in the short string. `-c`/`--frame_cnt` from the help text does not work. `--frame_cnt` is not in the table at all, and `-c` falls to usage. Use `--loop_count`.

## How it works

**What "wrap" means here.** Normally the ISP writes each full NV12 frame into a DDR buffer, and VENC encodes from that buffer once the frame is complete. In wrap mode:

- `RK_MPI_VI_SetChnWrapBufAttr(0, chn, {bEnable=1, u32BufLine=L, u32WrapBufferSize=width*L*3/2})` makes the VI channel write into a ring buffer only `L` lines high. Example: 1920 × 128 × 1.5 ≈ 368 KB instead of ≈ 3.1 MB per frame.
- `RK_MPI_VENC_SetChnBufWrapAttr(chn, {bEnable=1})` tells the encoder its input is such a wrapping buffer. The encoder then consumes lines while the ISP is still producing the frame.

This saves DDR (important on the RV1106 with 64–256 MB) and cuts capture-to-bitstream latency. Under the hood librockit uses rkisp private ioctls; it contains the strings `RKISP_CMD_SET_WRAP_LINE` and `RKISP_CMD_GET_WRAP_LINE`. The `maxWidth`/`maxHeight` options exist because the wrap and encoder buffers are sized for the sensor's maximum output.

Call sequence:

1. Parses options and prints `#Resolution:`, `#Sensor Max Resolution:`, `#Output Path: %d`, `#CameraIdx:` and `#Frame Count to save:`. Installs a SIGINT handler and calls `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr(0)` (if `0xA0088007`, `SetDevAttr`) → `RK_MPI_VI_GetDevIsEnable` → `RK_MPI_VI_EnableDev(0)` + `RK_MPI_VI_SetDevBindPipe(0,{0,0})`.
3. `vi_chn_init(chn, w, h, maxW, maxH)` fills a global `VI_CHN_ATTR_S`: w×h, NV12, depth 1, ISP buffer count 3, DMABUF, and max size = max(w, maxW) × max(h, maxH). Then `RK_MPI_VI_SetChnAttr(0, chn)`. If wrap is enabled:
   - checks `L` is in [128, h]; otherwise it prints `wrap mode buffer line must between [128, H]` and returns −1 **before** `EnableChn`
   - prints `set channel wrap line: %d, wrapBuffSize = %d`
   - `RK_MPI_VI_SetChnWrapBufAttr`

   Then `RK_MPI_VI_EnableChn(0, chn)`.

4. `RK_MPI_VI_ChnSaveFile(0, 0, {bCfg = -o value, "/userdata/", "venc_wrap_<camid>.bin"})`. Despite the name, this is the VI-side frame dump facility [INFERENCE].
5. VENC context setup (`0x1156c`) fills `VENC_CHN_ATTR_S`:
   - codec, max pic size = maxW × maxH, pixel format from VI
   - buffer size = maxW × maxH × 3/2
   - pic and virtual size = w × h, stream buffer count 5
   - RC mode 1 (`H264CBR` [INFERENCE]) with GOP 60 and bitrate 10240 kbit/s

   The RC mode is the same for every codec.

6. `vi_venc_wrap` (`0x11838`):
   - `RK_MPI_VENC_CreateChn(0)`
   - `RK_MPI_VENC_SetChnBufWrapAttr(0, {bEnable = VI wrap enabled})`
   - `RK_MPI_VENC_SetChnRefBufShareAttr(0, {bEnable = 0})`
   - if `--de_breath` ≠ 0: `RK_MPI_VENC_SetDeBreathEffect(0, {bEnable=1, …, strength = de_breath})`
   - `RK_MPI_VENC_StartRecvFrame(0, {loop_count})`
7. `RK_MPI_SYS_Bind({mod 8 VI, dev 0, chn camid} → {mod 4 VENC, 0, 0})`. On failure it prints `bind %d ch venc failed`.
8. Thread `vi_venc_wrap`/`GetMediaBuffer`:
   - `RK_MPI_VENC_GetStream(0, &stream, -1)`
   - prints `chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus`
   - `RK_MPI_VENC_ReleaseStream`
   - `usleep(1000)`

   It stops after `loop_count` frames.

9. Exit: `RK_MPI_VI_DisableChn(0, 0)` (hard-coded channel 0), `RK_MPI_VI_DisableDev(0)`, `test running exit:%d`, `RK_MPI_SYS_Exit`. There is no `SYS_UnBind`, `VENC_StopRecvFrame` or `VENC_DestroyChn`.

Bugs visible in the binary:

- **Defaults fail.** With the defaults (`--wrap` = 1, `--wrap_line` = 0, in `.bss`), the range check fails, VI `EnableChn` is skipped, and the return value is ignored. The VENC is then created without wrap and bound to a channel that never produces frames [INFERENCE: GetStream blocks forever]. You must pass e.g. `--wrap_line 256`.
- **`-o 1` probably crashes.** The thread writes the encoded stream with `fwrite(…, ctx->fp)` when the output flag is set, but the `FILE*` slot at `0x233d8+396` is never assigned, and the binary imports no `fopen`. So `-o 1` would call `fwrite` on a NULL stream and probably crash [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses rkisp video and media nodes, rkisp private ioctls (`RKISP_CMD_SET_WRAP_LINE`), the MPP encoder and the rockit MPI devices (`/dev/mpi/vvi`, `/dev/mpi/venc`, `/dev/mpi/vsys`, `/dev/mpi/valloc`) [INFERENCE from library strings].
- Files and paths read/written: with `-o 1`, rockit's VI save writes into `/userdata/` as `venc_wrap_<camid>.bin`. No other files.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** It is not referenced by any script in `downlaods/3/dump`, and `lp_app` does not depend on it. It is useful only as evidence that this firmware's librockit supports VI/VENC wrap mode. Whether `lp_app` uses wrap mode cannot be told from here. Running it while `lp_app` is up would contend for VI device 0, the rkisp main path and VENC channel 0. On exit it disables VI channel 0 regardless of `--camid`, which could tear down a channel `lp_app` is using [INFERENCE]. With `-o 1` it may write to `/userdata` (flash) or crash, as described above.

## Evidence

- `readelf -p .rodata`: `wrap mode buffer line must between [128, H]`, `set channel wrap line: %d, wrapBuffSize = %d`, `/userdata/`, `venc_wrap_%d.bin`, `create %d ch venc failed`, `bind %d ch venc failed`, `#Sensor Max Resolution: %dx%d`, long-option names `aiq pixel_format device_name camera_num width height maxWidth maxHeight wrap wrap_line codec de_breath loop_count output_path camid help`.
- Decoded long-option table:
  ```
  aiq 2 'a' | pixel_format 2 'f' | device_name 1 'd' | camera_num 1 'n' | width 1 'w' | height 1 'h'
  maxWidth 1 'W' | maxHeight 1 'H' | wrap 1 'r' | wrap_line 1 'L' | codec 1 'C' | de_breath 1 'D'
  loop_count 1 'l' | output_path 1 'o' | camid 1 'I' | help 2 '?'
  ```
- Jump table (`0x11d08`, base `'C'`): `C`→`0x11e78`, `D`→`0x11e98`, `H`→`0x11e3c`, `I`→`0x11e5c`, `L`→`0x11f28`, `W`→`0x11e1c`, `h`→`0x11dfc`, `l`→`0x11eb8`, `o`→`0x11ee0`, `r`→`0x11efc`, `w`→`0x11ddc`, everything else → usage `0x11f54`.
- Imports specific to this sample: `RK_MPI_VI_SetChnWrapBufAttr`, `RK_MPI_VENC_SetChnBufWrapAttr`, `RK_MPI_VENC_SetChnRefBufShareAttr`, `RK_MPI_VENC_SetDeBreathEffect`, `RK_MPI_VI_ChnSaveFile`, `getopt_long`. No `fopen*`.
- Disassembly:
  ```
  11c98: mov r3,#1920 ; 11ca0: movw r3,#1080 ; 11ca8: mov r3,#2560 ; 11cb0: mov r3,#1440 ; 11cd8: mov r3,#12 (codec)
  11ce8: mov r2,#1 ; str → 0x233bc (wrap enable)
  11450: ldr [0x233c0] ; cmp #127 ; bls error ; cmp h ; bhi error
  114c0..114dc: width*line*3/2 → wrapBuffSize ; 11518: bl RK_MPI_VI_SetChnWrapBufAttr
  11320: mov r3,#3 → VI buf count ; 113dc: mov r2,#1 → depth ; 11354: mov r2,#4 → mem type
  117b0: mov r2,#5 (stream buf cnt) ; 11598: mov r3,#10240 ; 11590: mov r3,#60
  11910: bl RK_MPI_VENC_SetChnBufWrapAttr ; 11940: bl RK_MPI_VENC_SetChnRefBufShareAttr ; 11994: bl RK_MPI_VENC_SetDeBreathEffect
  11a88: ldr r3,[r3,#396] → fwrite stream (slot never written: no store to +396 anywhere)
  ```
- `strings librockit.so`: `request RKISP_CMD_SET_WRAP_LINE error, err %d : %s`, `request RKISP_CMD_GET_WRAP_LINE error, err %d : %s`.

## Open questions

- Exact field names and enum values of `VENC_DEBREATHEFFECT_S`, `VENC_CHN_BUF_WRAP_S`, `VENC_CHN_REF_BUF_SHARE_S` and of the VENC attribute at offset 128 (= 1) are inferred from the SDK layout [INFERENCE].
- What `RK_MPI_VI_ChnSaveFile` writes when the channel is in wrap mode is not determinable statically.
- Whether `lp_app` uses wrap mode on this camera is unknown, because `lp_app` is not in this directory.
