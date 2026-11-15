# `simple_vi_rkaiq`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_rkaiq` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `19316` |
| sha256 | `5c934ea4bdb2a25d0f7c5b8aedba94dbb226a2f65c67170d39d14348b7f7adc1` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK `simple_test` sample `simple_vi_rkaiq` (with SDK `SAMPLE_COMM_ISP_*` helpers) |
| confidence | high |

## Summary

This is an SDK demo that brings up the camera input path. It can optionally start the rkaiq ISP 3A engine with an IQ-file directory. It then configures VI device 0 and one VI channel and pulls raw frames (`RK_MPI_VI_GetChnFrame`), logging per-frame and channel statistics. It can optionally have rockit dump the channel to a `.yuv` file. It is a bring-up/diagnostic tool and is not used by the production firmware.

## Usage

Verbatim help (printed for `?` or any unhandled option):

```
usage example:
	%s -I 0 -w 1920 -h 1080 -o 1
	-a | --aiq: iq file path, Default:/etc/iqfiles
	-w | --width: VI width, Default:1920
	-h | --heght: VI height, Default:1080
	-c | --frame_cnt: frame number of output, Default:-1
	-I | --camid: camera ctx id, Default 0. 0:rkisp_mainpath,1:rkisp_selfpath,2:rkisp_bypasspath
	-d | --hdr_mode: Default:0, 0:normal,1:hdr2
	-m | --multiple sensor: Default:0 
	-o: output path, Default:0  0 or 1 /data/test_0.yuv
```

`getopt` string: `"?::a::w:h:c:I:o:m:d:"`. Short options only. Behaviour from the code:

| opt | effect | default |
|---|---|---|
| `-a[path]` | Enables ISP/rkaiq. The argument is optional and must be attached (`-a/etc/iqfiles`). A bare `-a` uses `/etc/iqfiles` | **not set, so the ISP is not started** (the help implies `/etc/iqfiles`) |
| `-w` / `-h` | VI channel width/height | 1920 / 1080 |
| `-c` | stop after N frames | -1 (forever) |
| `-I` | VI channel id (0 mainpath, 1 selfpath, 2 bypass per the help) | 0 |
| `-d` | `1` selects HDR2 (working mode `0x10`); anything else means normal (0) | 0 |
| `-m` | multi-sensor flag passed to `SAMPLE_COMM_ISP_Init` | 0 |
| `-o <dir>` | Enables `RK_MPI_VI_ChnSaveFile` and copies the argument as the **directory**. The file name is `test_<chn>.yuv` | off (the placeholder dir is `/userdata/`) |

The help example `-o 1` therefore saves into a relative directory called `1`. To get `/data/test_0.yuv` you pass `-o /data/`.

## How it works

1. Parse options. Print `#####Aiq xml dirpath: %s` (only when `-a` is given), `#Resolution`, `#Output Path`, `#CameraIdx` and `#Frame Count to save`. Install a `SIGINT` handler.
2. If an IQ dir is set, call `SAMPLE_COMM_ISP_Init(0, hdr_mode, multi_sensor, iqdir)` and then `SAMPLE_COMM_ISP_Run(0)`. These call `rk_aiq_uapi2_sysctl_enumStaticMetas` → `rk_aiq_uapi2_sysctl_init` → `rk_aiq_uapi2_sysctl_prepare` → `rk_aiq_uapi2_sysctl_start`. For multi-sensor setups they use `rk_aiq_uapi2_camgroup_create/prepare/start` instead. Mirror/flip, frame-rate, scene-switch and LDCH helpers (`rk_aiq_uapi2_setMirrorFlip`, `rk_aiq_user_api2_ae_set/getExpSwAttr`, `rk_aiq_uapi2_sysctl_switch_scene`, `rk_aiq_user_api2_aldch_v21_*`) are linked in from the SDK common code.
3. `RK_MPI_SYS_Init`.
4. `vi_dev_init`: `RK_MPI_VI_GetDevAttr(0)`. If not configured: `RK_MPI_VI_SetDevAttr`, then `RK_MPI_VI_GetDevIsEnable` → `RK_MPI_VI_EnableDev(0)` → `RK_MPI_VI_SetDevBindPipe(0, pipe 0)`.
5. `vi_chn_init(-I, w, h)`: `RK_MPI_VI_SetChnAttr(0, chn, {w, h, 2 buffers, …})` then `RK_MPI_VI_EnableChn`.
6. `RK_MPI_VI_ChnSaveFile(0, chn, {bCfg = (-o given), dir, "test_%d.yuv"})`. This is always called, but saving is enabled only with `-o`.
7. Thread `GetMediaBuffer0` loops on `RK_MPI_VI_GetChnFrame(0, chn, &frame, 33 ms)`. On success it calls `RK_MPI_MB_Handle2VirAddr`, logs `RK_MPI_VI_GetChnFrame ok:data %p loop:%d seq:%d pts:%lld ms len=%d`, then calls `RK_MPI_VI_QueryChnStatus` and logs width, height, frame id, lost frames, framerate and vbfail. It then calls `RK_MPI_VI_ReleaseChnFrame`. On timeout it logs `RK_MPI_VI_GetChnFrame timeout %x`. It stops after `-c` frames.
8. Teardown: `RK_MPI_VI_DisableChn`, `RK_MPI_VI_DisableDev`, `SAMPLE_COMM_ISP_Stop(0)` (`rk_aiq_uapi2_sysctl_stop` and `rk_aiq_uapi2_sysctl_deinit`), `RK_MPI_SYS_Exit`.

There is no encoder and no network.

## Interfaces touched

- Device nodes / sysfs / procfs: none are named in the binary. Through librockit and librkaiq it uses `/dev/mpi/vvi`, `/dev/mpi/vsys`, `/dev/mpi/valloc`, the rkisp `/dev/video*` and `/dev/media*` nodes and the sensor subdevs [INFERENCE from library strings].
- Files and paths read/written: IQ files under the `-a` directory (`/etc/iqfiles` contains `CAC_sc4336_OT01_40IRC_F16`, `CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16` and `jx_f37p_AXF37AA_SR2012A.json`). With `-o <dir>`, rockit writes `<dir>/test_<chn>.yuv`.
- Network: none.
- Environment variables / config files: none read directly. librkaiq may honour its own environment variables, which were not analysed.

## Relevance on this camera

- It is not started at boot. There are no references in `RkLunch.sh`, either `init.d` directory or anywhere else in the dump.
- `lp_app` does not depend on it. `lp_app` itself calls `rk_aiq_uapi2_sysctl_init` and the VI API on the same sensor.
- Running this while `lp_app` is active would conflict on VI dev 0 / pipe 0 and the channels, and with `-a` on a second rkaiq instance for camera 0. Expect `RK_MPI_VI_*` errors or disturbed `lp_app` video [INFERENCE].
- Use `/mnt/sdcard/lp_stop` to keep `lp_app` from starting.
- Side effects: with `-o`, it writes a growing raw YUV file to the given directory. There are no GPIO/flash effects.

## Evidence

```
$ strings -t x simple_vi_rkaiq | grep -e '?::' -e test_ -e userdata
   4328 ?::a::w:h:c:I:o:m:d:
   ... /userdata/   test_%d.yuv
$ readelf -x .data simple_vi_rkaiq | grep 0x00024324
  0x00024324 ffffffff 3f3a3a61 ...    <- frame count default -1
```
Option table (`opt-'I'` jump table): `I`→chn, `a`→iq dir (optarg or "/etc/iqfiles"), `c`→count, `d`→hdr, `h`, `m`→multi, `o`→enable save + strcpy dir, `w`.
`main`:
```
11c4c..11c64: camid=0, iqdir=NULL, hdr=0, multi=0, save=0
11e98: if (iqdir) { printf("#####Aiq xml dirpath") ; 11ec0: hdr==1 ? 16 : 0
11ee0: bl 0x12408   ; SAMPLE_COMM_ISP_Init(0,hdr,multi,iqdir)
11ee8: bl 0x12914 } ; SAMPLE_COMM_ISP_Run(0)
11f5c: RK_MPI_SYS_Init ; 11f94 vi_dev_init ; 11fa8 vi_chn_init(camid,w,h)
11fe8: "/userdata/" (default dir) ; 12018 "test_%d.yuv" ; 12034 RK_MPI_VI_ChnSaveFile
1204c: pthread_create(GetMediaBuffer0)
```
Thread: `116d8: mov r3,#33` (timeout ms) … `11710: RK_MPI_VI_GetChnFrame`, `117b4: RK_MPI_VI_QueryChnStatus`, `11850: RK_MPI_VI_ReleaseChnFrame`.

## Open questions

- The VI channel attribute's pixel format and memory type constants were not decoded field-by-field.
- Whether channel ids 1/2 really map to rkisp selfpath/bypass on this sensor setup depends on the kernel/rockit configuration. The mapping comes only from the help text.
- The behaviour of librkaiq environment variables, if any, is outside this binary.
