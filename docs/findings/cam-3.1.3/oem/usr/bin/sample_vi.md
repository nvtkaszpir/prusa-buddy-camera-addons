# `sample_vi`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_vi` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `24000` |
| sha256 | `62a40768ec0465aca42be93acb9c531cca051096434d11347b85c8cd863d5ed4` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi example `sample_vi` (built from `media/samples/example/...` with the shared `SAMPLE_COMM_*` helpers). Prusa's CI built it; see the `Prusa-Cam-SOC-Linux-SDK` path in sibling samples. |
| confidence | high |

## Summary

This is the SDK's minimal camera-capture demo. It opens one VI (video input) device and channel on the ISP output through rockit. It can start the rkaiq 3A engine in-process. It then pulls raw YUV frames in a thread, optionally appends them to `/<output_path>/vi_<devId>.bin`, and prints one line per frame. It is a leftover developer/bring-up tool and is not part of the camera's runtime.

## Usage

The binary prints this text (function at `0x118dc`, via `puts`/`printf`) when `argc < 2` or when it gets an unhandled option:

```
usage example:
	%s -w 2560 -h 1520 -a /etc/iqfiles/ -l 10 -o /data/
	-a | --aiq: enable aiq with dirpath provided, eg:-a /etc/iqfiles/, set dirpath empty to using path by default, without this option aiq should run in other application
	-M | --multictx: switch of multictx in isp, set 0 to disable, set 1 to enable. Default: 0
	-d | --device_name: set pcDeviceName, eg: /dev/video0 Default NULL
	-I | --camid: camera ctx id, Default 0
	-n | --camera_num: camera number, Default 6
	-w | --width: camera with, Default 1920
	-h | --height: camera height, Default 1080
	-f | --pixel_format: camera Format, Default nv12, Value:nv12,nv16,yuyv,uyvy,afbc
	-l | --loop_count: loop count, Default -1
	-o | --output_path: vi output file path, Default NULL
```

The getopt string is `?::a::d:f:w:h:c:o:e:n:I:i:l:M:`. The long options were recovered from the `struct option` table at `0x13be8`:

| option | has_arg | handled? | effect (from the switch at `0x11cac`) |
|---|---|---|---|
| `-a`, `--aiq [dir]` | optional | yes | Sets the IQ directory. It also accepts a following non-`-` argv word. If no directory is given, the pointer stays NULL and AIQ is **not** started, despite the help text. |
| `-d`, `--device_name` | required | yes | Copied with `strcpy` into the VI context (the VI node/entity name). |
| `-f`, `--pixel_format` | optional | yes | `nv12`/`nv16`/`yuyv`/`uyvy`/`afbc`, compared with `strcmp`. |
| `-w`, `--width` / `-h`, `--height` | required | yes | Capture size. Defaults 1920×1080. |
| `-I`, `--camid` | required | yes | VI device id. Pipe = device. Default 0. |
| `-l`, `--loop_count` | required | yes | Number of frames to grab before quitting. Default -1 (endless). |
| `-o`, `--output_path` | required | yes | Directory for the dump file. Default NULL (nothing is written). |
| `-M`, `--multictx` | required | yes | Passed to `SAMPLE_COMM_ISP_Init`. |
| `-n`, `--camera_num` | required | **no** | Has no case. It falls to the default branch, which prints usage and exits 0. |
| `--fps` | required | aliased | Its `val` is `'f'`, so the value is parsed as a pixel-format name. |
| `--hdr_mode` | required | **no** | `val` 213 has no case, so usage is printed and the program exits. |
| `-c`, `-e`, `-i` | — | **no** | In the optstring only. Usage is printed and the program exits. |

## How it works

`main` is at `0x11bc4` (stripped binary, `-O0` code):

1. If `argc < 2`, it prints usage. Otherwise it allocates an 880-byte context with `malloc`+`memset` and installs `signal(SIGINT, handler)`. The handler prints `signal %d` and sets the global quit flag.
2. It parses the options with `getopt_long`, then prints `#CameraIdx`, `#pDeviceName`, `#Output Path` and `#IQ Path`.
3. If an IQ directory was given, it prints `#Rkaiq XML DirPath` and `#bMultictx`, then calls `SAMPLE_COMM_ISP_Init(camid, NORMAL, multictx, dir)` (`0x12e54`). That function does `setenv("HDR_MODE", ...)`, `rk_aiq_uapi2_sysctl_enumStaticMetas`, `rk_aiq_uapi2_sysctl_init`/`prepare`, and optionally `setMulCamConc`. It then calls `SAMPLE_COMM_ISP_Run` (`0x13360`), which calls `rk_aiq_uapi2_sysctl_start`.
4. `RK_MPI_SYS_Init`. It fills the context: width/height, devId = camid, pipeId = devId, chnId = 0, buffer count 3. If `-d` was given, it `strcpy`s the device name into the context.
5. `SAMPLE_COMM_VI_CreateChn` (`0x12448`) calls, in order: `RK_MPI_VI_GetDevAttr`, `RK_MPI_VI_SetDevAttr`, `RK_MPI_VI_GetDevIsEnable`, `RK_MPI_VI_EnableDev`, `RK_MPI_VI_SetDevBindPipe`, `RK_MPI_VI_SetChnAttr`, optionally `RK_MPI_VI_SetChnWrapBufAttr` (wrap mode, "wrap mode buffer line must between [128, %d]"), `RK_MPI_VI_EnableChn`, and optionally `RK_MPI_VI_ChnSaveFile`.
6. `pthread_create` starts the capture thread (`0x1198c`):
   - If an output path is set, it opens `snprintf("/%s/vi_%d.bin", out, devId)` with mode `"wb"`.
   - Loop: `SAMPLE_COMM_VI_GetChnFrame` (`RK_MPI_VI_GetChnFrame` + `RK_MPI_MB_Handle2VirAddr` + `RK_MPI_VI_QueryChnStatus`), then `fwrite` + `fflush` of the whole frame. It prints `SAMPLE_COMM_VI_GetChnFrame DevId %d ok:data %p size:%d loop:%d seq:%d pts:%lld ms`, then `RK_MPI_VI_ReleaseChnFrame` and `usleep(1000)`.
   - When `loop_count > 0` and the count is reached, it sets the quit flag.
7. `main` prints `main initial finish` and sleeps 1 s until the quit flag is set. It then `pthread_join`s, calls `SAMPLE_COMM_VI_DestroyChn` (`RK_MPI_VI_DisableChn`, `RK_MPI_VI_DisableDev`) and `RK_MPI_SYS_Exit`. If AIQ was started, it calls `SAMPLE_COMM_ISP_Stop` (`rk_aiq_uapi2_sysctl_stop` + `deinit`), then `free`.

There is no VPSS, VENC, RGN or network code; the imports are only `RK_MPI_VI_*`, `RK_MPI_SYS_*`, `RK_MPI_MB_Handle2VirAddr` and `rk_aiq_*`.

**Difference from `sample_multi_vi`:** the two binaries are near-identical builds of the same source family. `sample_vi` drives **one** camera, has the `-d/--device_name` and `-I/--camid` handlers (and imports `strcpy`), and uses the single-camera `SAMPLE_COMM_ISP_Init`/`Run`/`Stop` path. `sample_multi_vi` drops `-d`, makes `-n` work, loops over N cameras, and uses the camgroup AIQ API.

## Interfaces touched

- Device nodes / sysfs / procfs: none are referenced directly. librockit and librkaiq open the rkcif/rkisp V4L2 video and media nodes and the sensor subdevices [INFERENCE]. `-d` lets the user name a node such as `/dev/video0` (usage text).
- Files and paths read/written:
  - Writes `/<output_path>/vi_<devId>.bin` (raw frames, appended continuously) only when `-o` is given.
  - Reads the IQ JSON from the `-a` directory through librkaiq (`/etc/iqfiles` and `/oem/usr/share/iqfiles` exist in this dump).
- Network: none.
- Environment variables / config files: sets `HDR_MODE` (`setenv`) before AIQ init. IQ files come from the `-a` directory.

## Relevance on this camera

- It is not started at boot. A grep of the whole `downlaods/3/dump/` tree for `sample_vi` finds no reference outside the binary itself. Neither `RkLunch.sh`, `/etc/init.d/S*` nor `/oem/usr/etc/init.d/S10ntp` references it, and `lp_app` does not depend on it.
- If run while `lp_app` streams, it tries to configure and enable the same VI device/pipe 0 and (with `-a`) a second rkaiq instance on the same sensor. Expect `RK_MPI_VI_*` failures or disturbed 3A in `lp_app` [INFERENCE].
- Side effects are limited to the optional dump file. With `-o` pointing at flash (e.g. `/data`, `/userdata`) it writes full-size raw frames continuously until `-l` frames are captured. With the default `-l -1` it fills the partition.

## Evidence

- `python3 opts.py sample_vi` (parses the `struct option` table): `--aiq(2,a) --pixel_format(2,f) --device_name(1,d) --camera_num(1,n) --width(1,w) --height(1,h) --loop_count(1,l) --output_path(1,o) --camid(1,I) --multictx(1,M) --fps(1,f) --hdr_mode(1,213) --help(2,?)`.
- Jump-table decode of the switch at `0x11cac`: cases exist only for `a d f w h I l o M`. The default (`0x12040`) calls usage and returns 0.
- Main-flow excerpt (annotated `llvm-objdump`):
  ```
  1206c ; ="?::a::d:f:w:h:c:o:e:n:I:i:l:M:"   12078 bl getopt_long
  12110 bl SAMPLE_COMM_ISP_Init               12118 bl SAMPLE_COMM_ISP_Run
  1211c bl RK_MPI_SYS_Init                    12200 bl SAMPLE_COMM_VI_CreateChn
  12218 bl pthread_create                     12238 bl sleep
  12284 bl SAMPLE_COMM_VI_DestroyChn          12290 bl RK_MPI_SYS_Exit
  ```
- Capture-thread excerpt: `11a08 ="/%s/vi_%d.bin"`, `11a24 bl fopen64 ("wb")`, `11af4 bl fwrite`, `11b80 usleep(1000)`.
- `diff` of `strings` against `sample_multi_vi`: only `strcpy`, `device_name`, the `-d`/`-I` help lines, `#CameraIdx`/`#pDeviceName` vs `#CameraNum`, and the optstring differ.
- `grep -rlw sample_vi downlaods/3/dump` → only the binary itself.

## Open questions

- The exact meaning of every context field (offsets 136–188 are set to 0/−1/2/3/4) was not mapped to `VI_CHN_ATTR_S` members. They are most likely buffer count, memory type and the frame-rate fields [INFERENCE].
- The `RK_MPI_VI_GetChnFrame` timeout value was not traced.
- Whether a second VI user can coexist with `lp_app` depends on rockit's multi-process handling; this was not determinable statically.
