# `simple_vi_get_frame`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_get_frame` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `14296` |
| sha256 | `538ea08e4595dfd56dbaddd2afb7586d5cf0f7344a0bb0dd58aeaa5c6ed252ec` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_vi_get_frame`), unmodified test tool |
| confidence | high |

## Summary

Opens rockit VI device 0 / pipe 0 and one VI channel (an rkisp output path) at a chosen resolution in NV12. It then pulls frames in a loop and prints per-frame and channel-status statistics. Optionally it has rockit dump the channel's frames to `/userdata/test_<chn>.yuv`. It is a camera-pipeline test tool and is not used by the camera.

## Usage

Printed for any unhandled option (getopt string `?::w:h:c:I:o:`):

```
usage example:
	%s -I 0 -w 1920 -h 1080 -o 1
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-o: output path, Default:0  0 or 1 /data/test_0.yuv
```

- `-w`, `-h`: VI channel size. Default 1920×1080.
- `-c <n>`: stop after more than `n` frames. Default −1, meaning run until SIGINT. The global `.data` initialiser is `0xffffffff`.
- `-I <n>`: VI channel number, used as the channel ID in every VI call. Per the help text, 0 = `rkisp_mainpath`, 1 = `rkisp_selfpath`, 2 = `rkisp_bypasspath`. Default 0.
- `-o <anything>`: turns on saving. The argument is copied into the save path but then overwritten with `/userdata/`. So any value, including `0`, enables saving, and the file always goes to `/userdata/test_<camid>.yuv`, not the `/data/test_0.yuv` the help text claims.
- Long forms (`--width` etc.) are only text; the binary uses plain `getopt`.

## How it works

1. Parses options and prints `#Resolution:`, `#Output Path:` (only with `-o`), `#CameraIdx:` and `#Frame Count to save:`. Installs a SIGINT handler and calls `RK_MPI_SYS_Init`; on failure it logs `rk mpi sys init fail!`.
2. `vi_dev_init`:
   - `RK_MPI_VI_GetDevAttr(0)`. If it returns `0xA0088007` (VI "not configured"), it calls `RK_MPI_VI_SetDevAttr(0)` with a zeroed attribute; otherwise it prints `RK_MPI_VI_SetDevAttr already`.
   - `RK_MPI_VI_GetDevIsEnable(0)`. If the device is not enabled: `RK_MPI_VI_EnableDev(0)` and `RK_MPI_VI_SetDevBindPipe(0, {0, 0})`. Otherwise it prints `RK_MPI_VI_EnableDev already`.
3. `test_vi_init(chn, w, h)` fills `VI_CHN_ATTR_S`: size w×h, pixel format 0 (`RK_FMT_YUV420SP`/NV12), no compression, depth 2, ISP buffer count 2, memory type 4 (`VI_V4L2_MEMORY_TYPE_DMABUF`) [INFERENCE: field and enum names]. Then `RK_MPI_VI_SetChnAttr(0, chn)` and `RK_MPI_VI_EnableChn(0, chn)`; on failure it prints `ERROR: create VI error! ret=%d`.
4. Builds a `VI_SAVE_FILE_INFO_S` {enable = `-o` given, path `/userdata/`, name `snprintf("test_%d.yuv", chn)`} and calls `RK_MPI_VI_ChnSaveFile(0, chn, &info)`. With enable = 0 this is a no-op request [INFERENCE].
5. Thread `GetMediaBuffer0` loops:
   - `RK_MPI_VI_GetChnFrame(0, chn, &frame, 33 ms)`
   - `RK_MPI_MB_Handle2VirAddr`
   - prints `RK_MPI_VI_GetChnFrame ok:data %p loop:%d seq:%d pts:%lld ms len=%d`
   - `RK_MPI_VI_QueryChnStatus`, logged as `w:%d,h:%d,enable:%d,current frame id:%d,input lost:%d,output lost:%d,framerate:%d,vbfail:%d delay=%lldus`, where delay = `clock_gettime` now − frame PTS
   - `RK_MPI_VI_ReleaseChnFrame`

   A timeout logs `RK_MPI_VI_GetChnFrame timeout %x`. It stops when the loop count exceeds `-c`.

6. `main` polls the quit flag (`usleep`), then calls `RK_MPI_VI_DisableChn(0, chn)`, `RK_MPI_VI_DisableDev(0)`, logs `test running exit:%d`, and calls `RK_MPI_SYS_Exit`.

The frame data itself is never written by the program; only the rockit `ChnSaveFile` facility writes it. ISP control (3A, the IQ file) is not started by this binary: there are no `rk_aiq_*` imports. With a raw sensor, image quality depends on whether something else, such as `lp_app` or rkaiq inside rockit, runs the 3A [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses the rkisp/VI video nodes (`/dev/video*`, `/dev/media%d`) and the rockit MPI devices (`/dev/mpi/vvi`, `/dev/mpi/vsys`, `/dev/mpi/valloc`) [INFERENCE from librockit strings].
- Files and paths read/written: with `-o`, rockit writes `/userdata/test_<chn>.yuv`. `/userdata` is persistent flash storage.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** There are no references in `downlaods/3/dump` other than the binary itself, and `lp_app` does not depend on it. While `lp_app` is streaming, VI device 0 and the rkisp main path are already in use. This tool would see the device as already enabled and then try to reconfigure or enable the same channel. That would probably fail or disturb `lp_app`'s video [INFERENCE]. With `-o` it writes raw NV12 frames to `/userdata` (flash), roughly 3 MB per 1080p frame, which can fill the partition and wear the flash.

## Evidence

- `readelf -p .rodata`: the usage lines, `RK_MPI_VI_GetChnFrame ok:data %p loop:%d seq:%d pts:%lld ms len=%d`, the `RK_MPI_VI_QueryChnStatus …` format, `RK_MPI_VI_GetChnFrame timeout %x`, `/userdata/`, `test_%d.yuv`, `GetMediaBuffer0`, `vi_dev_init`.
- `readelf -x .data`: `0x000232cc ffffffff 3f3a3a77 3a683a63 3a493a6f 3a00`, which is frame count −1 followed by `?::w:h:c:I:o:`.
- Jump table at `0x11528` (base `'I'`): `I`→`0x11624` (camid), `c`→`0x11644` (frame count), `h`→`0x11604`, `o`→`0x1166c` (flag = 1 + strcpy), `w`→`0x115e4`, everything else → usage.
- Disassembly:
  ```
  10fdc: mov r3,#33 ...           11014: bl RK_MPI_VI_GetChnFrame(0, chn, &f, 33)
  11290: movt r3,#0xa008 → 0xa0088007 compare after RK_MPI_VI_GetDevAttr
  113a4: mov r3,#2 (depth) ; 113c8: mov r3,#4 (mem type) ; bl RK_MPI_VI_SetChnAttr ; bl RK_MPI_VI_EnableChn
  117d0: ="/userdata/" copied over the -o string ; 11800: snprintf("test_%d.yuv", chn) ; 1181c: bl RK_MPI_VI_ChnSaveFile
  ```

## Open questions

- Which sensor is attached and what its native resolution is cannot be determined from this binary. The defaults are only SDK defaults.
- Exact semantics and file size limit of `RK_MPI_VI_ChnSaveFile` are inside librockit [INFERENCE].
- Whether rockit starts rkaiq 3A on its own for VI on this firmware was not determined.
