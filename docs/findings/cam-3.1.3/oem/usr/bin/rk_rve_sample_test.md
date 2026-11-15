# `rk_rve_sample_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_rve_sample_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `21812` |
| sha256 | `1b633d74f7ff3cc1e4cf69c80c11924a2a9228f884bd31cb58a8cd206ed54c16` |
| linked libraries | `librockit.so, librve.so, libc.so.0` |
| origin | Rockchip RV1106 SDK RVE sample (`SAMPLE_IVE_*` / `SAMPLE_COMM_IVE_*` naming, built in a tree under `/home/cc/mksdk/rve/` according to librve's debug paths) |
| confidence | high (what it does); medium (what "RVE" hardware is) |

## Summary

A small self-test and demo for RVE, Rockchip's hardware vision accelerator. `librve.so` exposes it through an IVE-style API (`RK_MPI_IVE_*`, modelled on HiSilicon IVE) and drives it via `/dev/rve`. The program runs one of two samples: a 16×16 histogram self-test (default), or a Shi-Tomasi corner + NCC object-tracking demo on a 640×360 YUV file. It is an SDK test tool.

## Usage

There are no help strings. `main` (0x10cc0) only inspects the first character of `argv[1]`:

```
rk_rve_sample_test        # histogram test (no message printed)
rk_rve_sample_test 0      # "show histogram sample"        -> SAMPLE_IVE_TestHist
rk_rve_sample_test 1      # "show object tracking sample"  -> SAMPLE_IVE_Object_Tracking
```

Any other first character also runs the histogram test. `SIGINT` (2) and `SIGTERM` (15) are trapped; the handlers `SAMPLE_IVE_TestHist_HandleSig` and `SAMPLE_IVE_Object_Tracking_HandleSig` stop the loop and free memory.

## How it works

**What RVE is on this platform** (from library exports and strings):

- `librve.so` (SONAME `librve.so`, needs only libc) exports about 50 `RK_MPI_IVE_*` functions: `Init`/`Deinit`, `DMA`, `Query`, `Add`/`Sub`/`And`/`Or`/`Xor`, `Thresh*`, `Filter`, `Sobel`, `CannyEdge`, `MagAndAng`, `Dilate`/`Erode`, `Hist`, `EqualizeHist`, `Integ`, `CCL`, `CSC`, `Map`, `LBP`, `NCC`, `SAD`, `NormGrad`, `GradFg`, `GMM`/`GMM2`, `MatchBgModel`/`UpdateBgModel`, `LKOpticalFlow`/`LKOpticalFlowPyr`, `STCandiCorner`/`STCorner`, `Warp_Affine`, `Pyramid_*`, `OrdStatFilter`, `16BitTo8Bit`/`8BitTo8Bit`, `Cvt*`, `COMM_MmzAlloc*`.
- It also has internal symbols `init_rve_hal_func_entires`, `init_rve_params_to_regs_entries`, `rve_hal_ioctl_start/cmd/end` and `rk_ive_pp_*`.
- It opens `/dev/rve` and fetches rockit MMZ functions with `dlsym` (`RK_MPI_MMZ_Alloc`, `RK_MPI_MMZ_Free`, `RK_MPI_MMZ_FlushCacheVaddrStart/End`, `RK_MPI_MB_Handle2PhysAddr`).
- The kernel side is `/oem/usr/ko/rve.ko` ("Driver for rve device", compatible `rockchip,rve`, author putin.li@rock-chips.com, vermagic 5.10.110), with a job/fence scheduler (`rve_job_commit`, `rve_job_wait`, ...).
- So RVE is a fixed-function computer-vision engine (classic IVE operators: filtering, morphology, histogram, corner detection, optical flow, background modelling). Expanding the acronym as "Rockchip Vision Engine" is [INFERENCE].

**Program flow:**

- Memory: the binary defines local `SYS_MmzAlloc`, `SYS_MmzAlloc_Cached`, `SYS_MmzFlush_Start/End` and `SYS_MmzFree`. These wrap `RK_MPI_MMZ_Alloc` / `RK_MPI_SYS_MmzAlloc_Cached` / `RK_MPI_MB_Handle2PhysAddr/VirAddr` / `RK_MPI_MMZ_Free` from `librockit.so`. Cache sync is a DMA-buf `ioctl` on `RK_MPI_MMZ_Handle2Fd()`, cmd `0x40086200` = `DMA_BUF_IOCTL_SYNC` ("sync start failed %d" / "sync end failed %d").
- `RK_MPI_SYS_Init` and `RK_MPI_SYS_Exit` are defined inside this binary as stubs that just return 0 (`mov r0,#0; bx lr` at 0x10ee8 / 0x10ef0). The real rockit system init is never called.
- **Histogram test** (0x121f8):
  1. `SAMPLE_COMM_IVE_CreateImage` makes a 16×16 U8C1 image in MMZ, which is zeroed ("stSrc, vir: %llx, phy: %llx").
  2. `CreateMemInfo` allocates 1024 bytes (256 bins).
  3. `RK_MPI_IVE_Hist(&handle, src, dst, instant=1)`.
  4. `RK_MPI_IVE_Query(handle, &finish, 1)` is polled, with `usleep(100)` while it returns 0x41 (busy).
  5. The bins are checked ("Test HIST, pu32Hist[0] = %d", or "Test hist error..." / "Test mem error...") and it prints "Process success!".
- **Object tracking** (0x1399c):
  1. Opens `/root/data/stream/rocker_640x360_f300.yuv` for reading and `/root/output/ot_out_640x360_f300.yuv` for writing.
  2. For each frame: `SAMPLE_COMM_IVE_ReadFile`, then `SAMPLE_COMM_IVE_DmaImage` (`RK_MPI_IVE_DMA` + `Query`).
  3. Shi-Tomasi corners via `RK_MPI_IVE_STCandiCorner` + `RK_MPI_IVE_STCorner`, on the tracked object and on the current frame ("tracking obj corner num: %d", "current frame corner num: %d").
  4. Matching via `RK_MPI_IVE_NCC` ("search times: %d, match_pattern_num: %d"), then a motion vector computed with `sqrt` ("motion vector: %d, %d").
  5. Writes the frame with `SAMPLE_COMM_IVE_WriteFile`.
  6. Loops until EOF or a signal ("exit loop"), then `fclose` both files.
- `RK_MPI_IVE_Init` is not imported; the library presumably opens `/dev/rve` lazily on the first operation [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/dev/rve` (via `librve.so`)
  - MMZ / DMA buffers via `librockit.so`, which uses `/dev/mpi/valloc` [INFERENCE: from librockit strings]
  - `DMA_BUF_IOCTL_SYNC` on the DMA-buf fds
- Files and paths read/written (tracking mode only):
  - read: `/root/data/stream/rocker_640x360_f300.yuv`
  - written: `/root/output/ot_out_640x360_f300.yuv`
- Network: none
- Environment variables / config files: none found.

## Relevance on this camera

- Not started at boot and not referenced by any init script.
- `rve.ko` is shipped in `/oem/usr/ko/` but is **not** loaded by `/oem/usr/ko/insmod_ko.sh`, which loads `rga3.ko`, `mpp_vcodec.ko`, `rockit.ko`, etc. So `/dev/rve` should not exist after a normal boot, and the samples would fail unless `rve.ko` is loaded by hand [INFERENCE: not verified on a live device; the dump's `/dev` is empty of these nodes].
- `lp_app` does not link `librve.so`. In the dump only `libivs.so` (the intelligent video-analysis library) and this sample depend on it.
- The tracking input file and `/root` paths are not present in the dump, so `1` mode fails with "failed to open(%s)" unless the files are supplied.
- No flash, GPIO or reboot side effects. Loading `rve.ko` and running the sample while `lp_app` runs would only share MMZ memory [INFERENCE].

## Evidence

```
$ readelf -d rk_rve_sample_test | grep NEEDED
 librockit.so, librve.so, libc.so.0
$ llvm-nm-14 -D rk_rve_sample_test | grep ' U RK_'
 RK_MPI_IVE_DMA RK_MPI_IVE_Hist RK_MPI_IVE_NCC RK_MPI_IVE_Query RK_MPI_IVE_STCandiCorner RK_MPI_IVE_STCorner
 RK_MPI_MB_Handle2PhysAddr RK_MPI_MB_Handle2VirAddr RK_MPI_MB_VirAddr2Handle RK_MPI_MMZ_Alloc RK_MPI_MMZ_Free
 RK_MPI_MMZ_GetSize RK_MPI_MMZ_Handle2Fd RK_MPI_SYS_MmzAlloc_Cached RK_MPI_SYS_MmzFlushCache
# main
   10cf0: cmp r4, #1           ; argc
   10d08: cmp r3, #48          ; argv[1][0]=='0' -> puts("show histogram sample"); hist
   10d10: cmp r3, #49          ; '1' -> puts("show object tracking sample"); tracking
# stubs
   10ee8: mov r0, #0 ; bx lr   (RK_MPI_SYS_Init)
   10ef0: mov r0, #0 ; bx lr   (RK_MPI_SYS_Exit)
$ readelf -p .rodata rk_rve_sample_test
  [   518]  /root/data/stream/rocker_640x360_f300.yuv
  [   550]  /root/output/ot_out_640x360_f300.yuv
$ strings librve.so | grep -E '^/dev|mksdk'
 /dev/rve  /home/cc/mksdk/rve/librve/hal/rve_impl.c
$ modinfo oem/usr/ko/rve.ko
 description: Driver for rve device   author: putin.li@rock-chips.com   vermagic: 5.10.110 ...
$ grep -n 'rve' oem/usr/ko/insmod_ko.sh
 (no output)
```

## Open questions

- Whether the RV1106 silicon in this camera actually has the RVE block enabled in the device tree. `rve.ko` is shipped but not loaded, and the device tree is not in the dump.
- What the tracking demo writes to the output file: raw frames, or frames with markers drawn on them.
- The exact pass condition of the histogram test; upstream-style it expects `pu32Hist[0] == 256` [INFERENCE].
