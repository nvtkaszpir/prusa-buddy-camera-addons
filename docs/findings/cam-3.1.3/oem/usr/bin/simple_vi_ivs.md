# `simple_vi_ivs`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_vi_ivs` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `10112` |
| sha256 | `3f3234cc6bea5f83861c65aa2394d789b33a4f08a83855d49218bd9dae229e1b` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi "simple" sample (`simple_vi_ivs`), unmodified test tool |
| confidence | high (flow), medium (IVS attribute field names) |

## Summary

Binds VI channel 0 (1920×1080 NV12) to a rockit IVS ("intelligent video system") channel configured for **motion detection plus occlusion detection** (`IVS_MODE_MD_OD`). On every 10th result it prints the motion-detection bitmap to stdout as an ASCII grid of `0`/`1`. It runs until Ctrl-C. It is a demo/test tool and is not used by the camera.

## Usage

none found. The binary has no option parsing (no `getopt` import) and no usage text. It is run with no arguments, and everything is hard-coded:

- VI device 0, pipe 0, channel 0, 1920×1080, NV12
- IVS channel 0
- stop with SIGINT (Ctrl-C), which prints `signal 2`

## How it works

1. Installs a SIGINT handler and calls `RK_MPI_SYS_Init`.
2. `vi_dev_init`: `RK_MPI_VI_GetDevAttr(0)` (if `0xA0088007`, `RK_MPI_VI_SetDevAttr`) → `RK_MPI_VI_GetDevIsEnable` → `RK_MPI_VI_EnableDev(0)` + `RK_MPI_VI_SetDevBindPipe(0, {0,0})`.
3. VI channel 0: 1920×1080, NV12, no compression, depth 2, ISP buffer count 2, DMABUF memory. Then `RK_MPI_VI_SetChnAttr(0,0)` and `RK_MPI_VI_EnableChn(0,0)`.
4. IVS channel 0 via `RK_MPI_IVS_CreateChn(0, &attr)`. The 904-byte attribute struct is set as follows; field names are matched to the RV1106 rockit `IVS_CHN_ATTR_S` order [INFERENCE], the values come from the binary:

   | offset | value | probable field |
   |---|---|---|
   | 0 | 3 | `enMode = IVS_MODE_MD_OD` (motion + occlusion detection) |
   | 4 / 8 | 1920 / 1080 | `u32PicWidth` / `u32PicHeight` |
   | 12 | 0 | `enPixelFormat = RK_FMT_YUV420SP` |
   | 28 | 30 | `s32Gop` |
   | 32 / 36 | 0 / 0 | `bSmearEnable` / `bWeightpEnable` (off) |
   | 40 | 1 | `bMDEnable` |
   | 44 | 1 | `s32MDInterval` (every frame) |
   | 48 | 0 | `bMDNightMode` |
   | 52 | 0 | `u32MDSensibility` (left at 0) |
   | 56 | 1 | `bODEnable` |
   | 60 | 1 | `s32ODInterval` |
   | 64 | 7 | `s32ODPercent` (occlusion threshold, %) |

5. `RK_MPI_SYS_Bind({mod 8 VI, 0, 0} → {mod 20 IVS, 0, 0})` [INFERENCE: 20 = `RK_ID_IVS`]. Frames therefore flow from VI to IVS inside rockit; the program never calls `RK_MPI_IVS_SendFrame`.
6. Thread `GetMediaBuffer0`, until SIGINT:
   - `RK_MPI_IVS_GetResults(0, &info, -1)`; on failure it logs `RK_MPI_IVS_GetResults fail %x`
   - when `frameCount % 10 == 0` and `info.s32ResultNum == 1`, it reads the result block pointer `pstResults`:
     - row count = `*(u32*)(res+0x1000C) >> 6`
     - bitmap = `*(u8**)(res+0x10008)`, stride 64 bytes per row
     - row width = `(1920+63)/64` = 30 bytes
   - prints a separator of `8*30` `-` characters, then for each row 30 bytes × 8 bits as `1`/`0` (LSB first), then another separator
   - `RK_MPI_IVS_ReleaseResults(0, &info)`

   Each output column is probably an 8-pixel-wide block, giving 240 columns across 1920 px, and each row an 8-line block [INFERENCE].

7. Teardown: `RK_MPI_SYS_UnBind`, `RK_MPI_IVS_DestroyChn(0)`, `RK_MPI_VI_DisableChn(0,0)`, `RK_MPI_VI_DisableDev(0)`, `RK_MPI_SYS_Exit`.

**Occlusion detection** is enabled in the attributes, but the program never reads or prints any OD result. Only the MD bitmap is shown. Smear and weight-P (encoder assist) are disabled.

**Relation to `libivs.so`:** the binary does **not** link or load `/oem/usr/lib/libivs.so`. Its only IVS interface is `RK_MPI_IVS_*` in `librockit.so`, which are real implementations (branch thunks into rockit code, node name `"rk_ivs"`). `libivs.so` is a separate software motion-detection library: it exports `RK_IVS_MD_Init/CreateChn/Process/GetBg`, GMM2 background-model helpers (`RK_IVS_GMM2_*`), the string `IVS MD version: 1.0.3`, and uses `RK_MPI_IVE_Erode`. Nothing in `/oem/usr/lib` references it, so it is presumably for `lp_app` [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Through librockit it uses the rkisp/VI video nodes and the rockit MPI devices (`/dev/mpi/vvi`, `/dev/mpi/vsys`, `/dev/mpi/valloc`); the IVS block itself is reached through librockit [INFERENCE: exact device not identifiable in this binary].
- Files and paths read/written: none. Output goes to stdout only.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

**Not started at boot.** It is not referenced by any script in `downlaods/3/dump`, and `lp_app` does not depend on it. It shows that this firmware's librockit has the hardware/firmware IVS MD+OD path. Whether `lp_app` uses rockit IVS, `libivs.so` or both for its motion detection cannot be told from here.

Running it while `lp_app` is up would contend for VI device 0 / channel 0 (rkisp main path). On exit it disables VI channel 0 and VI device 0, which would probably break `lp_app`'s video [INFERENCE]. It has no persistent side effects.

## Evidence

- `readelf -p .rodata`: `RK_MPI_IVS_GetResults fail %x`, `GetMediaBuffer0`, `vi_dev_init`, `ERROR: create VI error! ret=%d`. There are no usage strings.
- Imports: `RK_MPI_IVS_{CreateChn,DestroyChn,GetResults,ReleaseResults}`, `RK_MPI_VI_*`, `RK_MPI_SYS_{Bind,UnBind}`, `pthread_create`, `putchar`. No `getopt`, `fopen` or `RK_MPI_IVS_SendFrame`.
- Disassembly of IVS init (`0x11210`):
  ```
  11238: mov r3,#3   ; str [fp,-908]   enMode
  11240/48: width/height (1920/1080 from main 112cc)
  11258: mov r3,#30  ; str [fp,-880]
  11270: mov r3,#1   ; str [fp,-868]   (MD enable)
  11278: mov r3,#1   ; str [fp,-864]
  11288: mov r3,#1   ; str [fp,-852]   (OD enable)
  11290: mov r3,#1   ; str [fp,-848]
  11298: mov r3,#7   ; str [fp,-844]
  112ac: bl RK_MPI_IVS_CreateChn(0,&attr)
  11310: mov r3,#8 (VI) ; 11328: mov r3,#20 (IVS) ; 11350: bl RK_MPI_SYS_Bind
  ```
- Result printing: `10d98` (×0x66666667 → `%10`), `10dc4: cmp r3,#1` (result count), `10dec: add r3,#65536 ; ldr [r3,#12] ; lsr #6`, `10e04: ldr [r3,#8]` (bitmap pointer), `putchar('-'/'1'/'0'/'\n')`.
- `llvm-nm-14 -D librockit.so | grep IVS` → `RK_MPI_IVS_{Init,Exit,CreateChn,DestroyChn,SetChnAttr,GetChnAttr,SendFrame,GetResults,ReleaseResults}` defined. `llvm-objdump` shows each is a `b` into rockit code, not a stub.
- `readelf -d librockit.so` NEEDED: `librockchip_mpp.so.1 libaec_bf_process.so librkaudio_detect.so librga.so libstdc++.so.6 libgcc_s.so.1 libc.so.0`, with no `libivs.so`. `grep -rl libivs oem/usr/lib lib` finds only `libivs.so` itself.

## Open questions

- Exact `IVS_CHN_ATTR_S`/`IVS_RESULT_INFO_S` layouts. The offsets above are firm; the names and the 8×8-block interpretation are [INFERENCE].
- Whether rockit's IVS is computed by hardware (the VEPU/ISP statistics path) or in software inside librockit cannot be determined from this binary [INFERENCE].
- What the OD result looks like and where it lives in the result struct, since the program never reads it.
