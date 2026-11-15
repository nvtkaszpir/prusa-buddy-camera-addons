# `sample_vi_vpss_osd_venc`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_vi_vpss_osd_venc` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `125600` |
| sha256 | `a10963ac54fbf4e9573a17b2476d4a76712b682a3f68de63d02dc648021efbd2` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi example `sample_vi_vpss_osd_venc`, with the statically linked `rtsp_demo` server. Built by Prusa CI: it embeds `/home/runner/work/Prusa-Cam-SOC-Linux-SDK/Prusa-Cam-SOC-Linux-SDK/media/samples/common/loadbmp.c`. |
| confidence | high |

## Summary

This is a full demo pipeline: camera VI, then VPSS (scale to 1920×1080), then the VENC H.264/H.265 encoder. It adds two RGN regions on the encoder channel: a solid cover rectangle and an optional BMP logo overlay. The encoded stream is served over RTSP at `rtsp://<ip>:554/live/0` and can also be dumped to `/<output_path>/venc_0.bin`. It is an SDK demo, not used by the production firmware.

## Usage

```
usage example:
	%s -w 2560 -h 1520 -a /etc/iqfiles/ -I 0 -e h264cbr -b 4096 -i /usr/share/image.bmp -o /data/
	rtsp://xx.xx.xx.xx/live/0, Default OPEN
	-a | --aiq: enable aiq with dirpath provided, eg:-a /etc/iqfiles/, set dirpath empty to using path by default, without this option aiq should run in other application
	-M | --multictx: switch of multictx in isp, set 0 to disable, set 1 to enable. Default: 0
	-d | --device_name: set pcDeviceName, eg: /dev/video0 Default NULL
	-I | --camid: camera ctx id, Default 0
	-w | --width: camera with, Default 1920
	-h | --height: camera height, Default 1080
	-e | --encode: encode type, Default:h264cbr, Value:h264cbr, h264vbr, h264avbr h265cbr, h265vbr, h265avbr, mjpegcbr, mjpegvbr
	-b | --bitrate: encode bitrate, Default 4096
	-i | --input_bmp_name: input file path of logo.bmp, Default NULL
	-l | --loop_count: loop count, Default -1
	-o | --output_path: encode save file path, Default /data/
	-D | --disp devid: display DevId, Default -1
	-L | --disp layerid: display LayerId, Default 0
```

The getopt string is `?::a::b:w:h:l:o:e:d:D:I:i:L:M:`. Long options (table at `0x27ee8`): `aiq, bitrate, device_name, width, height, input_bmp_name, loop_count, output_path, encode, camid, multictx, fps('f'), hdr_mode(213), help`. Cases decoded from the jump table at `0x132b8`: `a b d D e w h I i l L o M`.

- `-e` maps to (codec, RC mode):
  - `h264cbr` 5/1, `h264vbr` 5/2, `h264avbr` 5/3
  - `h265cbr` 6/8, `h265vbr` 6/9, `h265avbr` 6/10
  - `mjpegcbr` 8/5, `mjpegvbr` 8/6
  - Anything else prints `ERROR: Invalid encoder type.` and exits.
- **MJPEG does not work:** the RTSP setup accepts only codec 5 (H.264) or 6 (H.265). Otherwise it prints `not support other type` and `main` returns -1 before `RK_MPI_SYS_Init`.
- `-o`: the actual default is NULL (local at `-48` is initialised to 0). With no `-o`, no file is written, despite "Default /data/" in the help.
- `-a` without a directory leaves the IQ path NULL, so AIQ is not started.
- `-D`/`-L` select a display device/layer. The VO helpers are compiled as empty stubs (`0x16ab0`/`0x16adc` just return 0) and no `RK_MPI_VO_*` is imported (see How it works).
- `--fps` (`'f'`) and `--hdr_mode` (213) have no case. They print usage and exit.

## How it works

`main` is at `0x1318c`:

1. Defaults: VI 1920×1080, VENC 1920×1080, H264 CBR, bitrate 4096, loop -1, display dev -1. It allocates and zeroes the context and installs `signal(SIGINT)`.
2. It parses the options and prints `#CameraIdx`, `#pDeviceName`, `#CodecName`, `#Output Path` and `#IQ Path`. If `-a dir` was given, it calls `SAMPLE_COMM_ISP_Init(camid, NORMAL, multictx, dir)` and `SAMPLE_COMM_ISP_Run` (`rk_aiq_uapi2_sysctl_init/prepare/start`).
3. RTSP: `rtsp_new_demo(554)`, then `rtsp_new_session(demo, "/live/0")` and `rtsp_set_video(session, 1=H264 | 2=H265, NULL, 0)`, then the timestamp sync calls.
4. `RK_MPI_SYS_Init`.
5. **VI:** `SAMPLE_COMM_VI_CreateChn`: dev = camid, pipe = dev, chn = 1, buffer count 3, size `-w`×`-h`. Optionally `strcpy` of the `-d` name. API calls: `RK_MPI_VI_SetDevAttr`, `EnableDev`, `SetDevBindPipe`, `SetChnAttr`, `EnableChn`.
6. **VPSS:** `SAMPLE_COMM_VPSS_CreateChn`: group 0, channel 0 output 1920×1080. The group crop ratio is computed as `1000*1920/w`. Channel 1 is configured only when `-D >= 0`. API calls: `RK_MPI_VPSS_CreateGrp`, `SetVProcDev`, `SetGrpCrop`, `SetChnAttr`, `SetChnRotation`, `EnableChn`, `StartGrp`.
7. **VENC:** `SAMPLE_COMM_VENC_CreateChn`: codec/RC from `-e`, bitrate `-b`, 1920×1080, constants 30 and 50 stored next to the bitrate (frame rate / GOP [INFERENCE]). API calls: `RK_MPI_VENC_CreateChn`, `SetRcParam`, optional `SetChnBufWrapAttr`/`EnableSvc`/`EnableMotionDeblur`, `StartRecvFrame`. It also starts the `venc_get_stream` thread (`0x12f08`).
8. **RGN** (both attached to VENC channel 0; type values follow rockit `RGN_TYPE_E`):
   - handle 0, type 2 (`COVER_RGN`): rect x=1328 y=976 w=576 h=96, colour `0xF800`, layer 1.
   - handle 1, type 0 (`OVERLAY_RGN`): rect (0,0,576,288), pixel format `0x10015` (an ARGB format), bg/fg alpha 128, bitmap from `-i`. It is loaded by `test_rgn_load_bmp` (`OSD_LoadBMP`/`load_bmp_ex` in `loadbmp.c`), then `RK_MPI_RGN_SetBitMap`.
   - Both go through `SAMPLE_COMM_RGN_CreateChn`: `RK_MPI_RGN_Create`, `AttachToChn`, optionally `SetBitMap`, `GetDisplayAttr`, `SetDisplayAttr`.
9. **Binds** (`SAMPLE_COMM_Bind` → `RK_MPI_SYS_Bind`), in order:
   1. VI (mod 8, dev, chn) → VPSS (mod 6, grp, 0)
   2. VPSS (mod 6, grp, chn0) → VENC (mod 4, 0, venc chn)
   3. VPSS (mod 6, grp, 1) → VO (mod 9, dev, layer), only if `-D >= 0`. The VO side is a stub, so this bind would fail [INFERENCE].
10. The `venc_get_stream` thread:
   - If `-o` is set, it opens `/%s/venc_%d.bin` with `"wb"`.
   - Loop: `SAMPLE_COMM_VENC_GetStream`. On reaching `loop_count` it releases and sets quit. Otherwise it `fwrite`s and `fflush`es the packet (if a file is open), sends it to RTSP (`rtsp_tx_video`) and services clients (`rtsp_do_event`), logs `chn:%d, loopCount:%d wd:%d`, calls `ReleaseStream` and `usleep(1000)`.
11. `main` sleeps 1 s until quit. Teardown runs in reverse: join, `rtsp_del_demo`, UnBind in reverse order, VO stub destroy, `SAMPLE_COMM_RGN_DestroyChn` ×2 (`DetachFromChn` + `Destroy`), VENC destroy, VPSS destroy, VI destroy, `RK_MPI_SYS_Exit`, `SAMPLE_COMM_ISP_Stop`.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. It uses the VI/ISP V4L2 nodes, the encoder and the RGA/VPSS hardware through librockit/MPP [INFERENCE].
- Files and paths read/written:
  - Reads the BMP given with `-i` (`fopen`/`fread`/`fseek`). The example `/usr/share/image.bmp` does not exist in this dump.
  - Writes `/<output_path>/venc_0.bin` (raw H.264/H.265 elementary stream) when `-o` is given.
  - Reads IQ files from the `-a` directory.
- Network: an RTSP server on TCP **554** with session path `/live/0`. RTP/RTCP is served over UDP (dynamic local ports) or interleaved over TCP. Logs: "rtsp server demo starting on port %d", "new rtsp client %s:%u comming".
- Environment variables / config files: `HDR_MODE` is `setenv`'d in the ISP init helper.

## Relevance on this camera

- It is not started at boot and is not referenced anywhere in the dump (`grep -rlw` finds only the binary). `lp_app` does not depend on it.
- If run while `lp_app` is up, the RTSP `bind()` on port 554 fails if `lp_app` already serves RTSP on 554 ("bind socket to address failed") [INFERENCE: lp_app's port is not visible here]. It also competes for VI dev 0, VPSS group 0 and VENC channel 0 [INFERENCE].
- Side effects: it opens an unauthenticated RTSP stream of the camera on the network. With `-o` it writes an unbounded stream file (default loop -1). Nothing is written to flash otherwise.

## Evidence

- `python3 opts.py` → the long-option table above. Jump table at `0x132b8` → cases `a b d D e w h I i l L o M`.
- `-e` parsing excerpt: `134d4 ="h264cbr" ... mov r3,#5 ; str [-52] ; mov r3,#1 ; str [-56] ; ="H264"`, `13684 ="mjpegcbr" ... mov r3,#8 ; mov r3,#5 ; ="MJPEG"`.
- RTSP setup excerpt:
  ```
  138e4 movw r0,#554 ; bl rtsp_new_demo
  1390c ="/live/0"   ; bl rtsp_new_session
  1392c cmp r3,#5 ; mov r1,#1 ; bl rtsp_set_video
  13958 cmp r3,#6 ; mov r1,#2 ; bl rtsp_set_video
  13984 ="not support other type"  -> return -1
  ```
- Bind excerpt: `14034 mov r3,#8 (src mod) ... mov r3,#6 (dst mod) bl SAMPLE_COMM_Bind`, `14088 #6 -> #4`, `140d8 cmp [-68],#0 ; blt skip ; #6 chn1 -> #9`.
- VO stub: `16ab0: str r11,[sp,#-4]! ... mov r0,#0 ; bx lr` (no calls). `grep VO` in the strings: 0 hits.
- `grep -rlw sample_vi_vpss_osd_venc downlaods/3/dump` → only the binary.

## Open questions

- The exact frame rate, GOP and profile fields given to VENC (constants 30, 50, 100 at context offsets 1784/1788/1836) were not mapped to `VENC_CHN_ATTR_S` members.
- Whether `lp_app` uses RTSP port 554 (and so collides) cannot be determined from this binary.
- The meaning of the second VPSS channel's rotation check (`cmp ...,#3` swaps w/h) is only relevant to the stubbed display path.
