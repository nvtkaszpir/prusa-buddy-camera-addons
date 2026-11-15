# `sample_multi_vi`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_multi_vi` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `23996` |
| sha256 | `d271dce45d3e8c68ed4678656eb1ea556ff0748092d01da8ed215c7cb8a6917f` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi example `sample_multi_vi` (the multi-sensor variant of `sample_vi`, using the shared `SAMPLE_COMM_*` helpers) |
| confidence | high |

## Summary

This is the multi-camera version of `sample_vi`. It opens N VI devices (default 6), each on its own pipe, channel 0. It can optionally run rkaiq in camera-group mode (`rk_aiq_uapi2_camgroup_*`). One thread per camera pulls raw frames and optionally dumps them to `/<output_path>/vi_<i>.bin`. It exists to test multi-sensor boards. This camera has a single sensor, so the program has no use here.

## Usage

Printed by the usage function (`0x118a4`) when `argc < 2` or when it gets an unhandled option:

```
usage example:
	%s -w 2560 -h 1520 -a /etc/iqfiles/ -n 6 -l 10 -o /data/
	-a | --aiq: enable aiq with dirpath provided, eg:-a /etc/iqfiles/, set dirpath empty to using path by default, without this option aiq should run in other application
	-M | --multictx: switch of multictx in isp, set 0 to disable, set 1 to enable. Default: 0
	-n | --camera_num: camera number, Default 6
	-w | --width: camera with, Default 1920
	-h | --height: camera height, Default 1080
	-f | --pixel_format: camera Format, Default nv12, Value:nv12,nv16,yuyv,uyvy,afbc
	-l | --loop_count: loop count, Default -1
	-o | --output_path: vi output file path, Default NULL
```

The getopt string is `?::a::f:w:h:c:o:e:n:I:i:l:M:`. The long-option table is at `0x13d4c`. Switch cases decoded from the jump table at `0x11c54`:

| option | handled? | effect |
|---|---|---|
| `-a`, `--aiq [dir]` | yes | IQ directory. Without a directory the pointer stays NULL and AIQ is not started. |
| `-f`, `--pixel_format` | yes | `nv12`/`nv16`/`yuyv`/`uyvy`/`afbc`. `--fps` shares `val` `'f'`, so it lands here too. |
| `-w` / `-h` | yes | Size for all cameras. Defaults 1920×1080. |
| `-n`, `--camera_num` | yes | Number of cameras. Default 6. `atoi` with no range check (see below). |
| `-l`, `--loop_count` | yes | Frames per camera before quitting. Default -1. |
| `-o`, `--output_path` | yes | Dump directory. Default NULL. |
| `-M`, `--multictx` | yes | Passed to the camgroup init. |
| `-I`, `--camid` | **no** | It still has a long option, but there is no case, so usage is printed and the program exits 0. |
| `--hdr_mode`, `-c`, `-e`, `-i` | **no** | Usage is printed and the program exits. |

There is no `-d/--device_name` (the long option and `strcpy` import were removed compared with `sample_vi`).

## How it works

`main` is at `0x11b74`:

1. Defaults: width 1920, height 1080, camera_num 6, loop -1. It allocates the context array with `malloc(5280)`, which is 6 × 880-byte per-camera contexts, then `memset` and `signal(SIGINT, ...)`.
2. It parses the options and prints `#CameraNum`, `#Output Path` and `#IQ Path`.
3. If an IQ directory is set, it prints `#Rkaiq XML DirPath`/`#bMultictx` and fills a 60-byte camgroup config: `sns_num = camera_num`, `iqfile path = dir`. It then calls `SAMPLE_COMM_ISP_CamGroup_Init(0, NORMAL, multictx, &cfg)` (`0x13118`). That function runs `rk_aiq_uapi2_sysctl_enumStaticMetas` for each sensor ("CamGroupId:%d, cam_id: %d, sensor_name is %s, iqfiles is %s"), then `rk_aiq_uapi2_camgroup_create`, `..._prepare` and `..._start`.
4. `RK_MPI_SYS_Init`. Then for `i = 0 .. camera_num-1`:
   - It fills `ctx[i]`: width/height, devId = i, pipeId = i, chnId = 0, buffer count 3, output path, loop count.
   - It calls `SAMPLE_COMM_VI_CreateChn(&ctx[i])`, the same VI call sequence as `sample_vi` (GetDevAttr/SetDevAttr, EnableDev, SetDevBindPipe, SetChnAttr, optional wrap, EnableChn).
   - It runs `pthread_create(..., thread 0x1193c, &ctx[i])`. The thread body is identical to `sample_vi`'s: `/%s/vi_%d.bin` with `"wb"`, then `GetChnFrame`, `fwrite`, `ReleaseChnFrame`, `usleep(1000)`, stopping at `loop_count`.
5. It waits on the quit flag (1 s `sleep` loop), joins all N threads, and calls `SAMPLE_COMM_VI_DestroyChn` for each, then `RK_MPI_SYS_Exit`. If AIQ was used, it calls `SAMPLE_COMM_ISP_CamGroup_Stop` (`0x13408`: `rk_aiq_uapi2_camgroup_stop` / `..._destroy`).

The VI channels are not bound to anything (no VPSS/VENC/RGN imports).

**Difference from `sample_vi`:** this binary loops over N cameras with a per-camera thread and uses the camgroup AIQ path instead of the single-context `sysctl` path. `-n` works and `-d`/`-I` are gone. The dump file name index is the loop index. The binary is 4 bytes smaller and imports no `strcpy`.

## Interfaces touched

- Device nodes / sysfs / procfs: none are referenced directly. It uses VI devices 0..N-1 through librockit (rkcif/rkisp V4L2 nodes) and sensors through librkaiq [INFERENCE].
- Files and paths read/written:
  - Writes `/<output_path>/vi_<i>.bin` per camera when `-o` is given.
  - Reads IQ files from the `-a` directory.
- Network: none.
- Environment variables / config files: `HDR_MODE` is set via `setenv` in the shared ISP init helper (present in the binary). The camgroup path does not appear to call it [INFERENCE].

## Relevance on this camera

- It is not started at boot and is not referenced anywhere in the dump (`grep -rlw sample_multi_vi` finds only the binary). `lp_app` does not use it.
- The board has one sensor (the IQ directories contain sc4336, sc530ai and jx_f37p profiles, one sensor fitted at a time). With the default `-n 6`, VI devices 1..5 would fail to enable [INFERENCE].
- `-n` is not bounds-checked against the 6-entry context array. `-n 7` or more would write past the `malloc(5280)` buffer [INFERENCE from code: the `n` handler is just `atoi` + store].
- Running it alongside `lp_app` conflicts on VI device 0 and the ISP, the same as `sample_vi` [INFERENCE].
- Side effects: only the optional dump files.

## Evidence

- `python3 opts.py sample_multi_vi`: `--aiq(2,a) --pixel_format(2,f) --camera_num(1,n) --width --height --loop_count --output_path --camid(1,I) --multictx(1,M) --fps(1,f) --hdr_mode(1,213) --help`.
- Jump table at `0x11c54`: cases `a f w h n l o M` only.
- `diff` of `strings` vs `sample_vi`:
  ```
  <  strcpy
  <  device_name
  <  %s -w 2560 -h 1520 -a /etc/iqfiles/ -l 10 -o /data/
  >  %s -w 2560 -h 1520 -a /etc/iqfiles/ -n 6 -l 10 -o /data/
  <  -d | --device_name ...   <  -I | --camid ...
  <  #CameraIdx: %d  #pDeviceName: %s   >  #CameraNum: %d
  <  ?::a::d:f:w:h:c:o:e:n:I:i:l:M:   >  ?::a::f:w:h:c:o:e:n:I:i:l:M:
  ```
- Per-camera loop excerpt: `120e4 mov r0,#880; mul ...` (context stride), `122c8 bl SAMPLE_COMM_VI_CreateChn`, `122fc bl pthread_create (=0x1193c)`, `12318 blt` (loop while i < camera_num).
- Camgroup strings: `rk_aiq_uapi2_camgroup_create over`, `rk_aiq_uapi2_camgroup_prepare over`, `rk_aiq_uapi2_camgroup_start over`, `pCamGroupCfg->sns_ent_nm_array[%d] is %s`.

## Open questions

- How librkaiq camgroup mode behaves with only one physical sensor present was not determinable statically.
- Whether `RK_MPI_VI_*` returns cleanly for non-existent VI devices 1..5 or blocks was not determinable statically.
