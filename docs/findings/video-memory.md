# Video memory

How the camera's 64 MB of RAM is split, what the 24 MB reserved for video buffers is used for, and whether it
could be smaller. Read-only checks on the maintainer's camera (firmware 3.1.3, kernel 5.10.110) on 2026-11-16,
with `lp_app` streaming.

## Summary

- Of the 64 MB of RAM, the kernel image takes about 6 MB and 24 MB is reserved for video buffers (CMA, a
  contiguous area for camera, ISP and encoder buffers). Linux manages the remaining 34,328 kB (`MemTotal`).
- `lp_app`'s 1080p30 video pipeline uses 23,208 KiB of the 24,576 KiB reserved area, leaving about 1.3 MB.
  The allocations below add up exactly to that figure, so the reservation is sized for this pipeline, not padded.
- Reserving less would only make `lp_app`'s buffer allocations fail and break video. Real savings need fewer
  or smaller buffers in `lp_app`, which is closed source and has no known setting for them.
- For other programs, about 4.8 MB is available (`MemAvailable`) while `lp_app` runs. There is no swap; see
  [Swap](swap.md).

## RAM layout

| Part | Size | Source |
|---|---|---|
| Physical RAM | 65,536 KiB (64 MB) | `/proc/iomem` (`00000000-03ffffff : System RAM`), `/proc/rk_memblock/memory` |
| Kernel image | 6,054 KiB | `/proc/rk_memblock/reserved`, entry `0x000081c0..0x005f1a6f` |
| Reserved for video buffers | 24,576 KiB (24 MB) | `rk_dma_heap_cma=24M` (kernel command line), `/proc/rk_cma/*` |
| All reserved at boot | 31,388 KiB | `/proc/rk_memblock/reserved` (kernel, video area at `0x0277b000`, small blocks) |
| Managed by Linux (`MemTotal`) | 34,328 kB | `/proc/meminfo` |
| Free (`MemFree`) | 1,532 kB | `/proc/meminfo` |
| Available (`MemAvailable`) | 4,820 kB | `/proc/meminfo`: free memory plus cache the kernel can drop |
| Swap | 0 | the kernel has no swap support |

The 24 MB size is set by the bootloader on the kernel command line (`rk_dma_heap_cma=24M`).

Where the 34 MB managed by Linux goes (`/proc/meminfo`):

| Use | kB |
|---|---|
| Program memory (`AnonPages`, mostly `lp_app`) | 12,900 |
| Kernel objects (`Slab`; 3,232 kB reclaimable) | 9,000 |
| Kernel virtual memory (`VmallocUsed`) | 4,916 |
| File cache (`Cached` + `Buffers`) | 3,284 |
| Kernel stacks and page tables | 1,592 |
| Free | 1,532 |

`Committed_AS` (133,048 kB) is far above `CommitLimit` (17,164 kB). That is address space programs have
reserved, not memory in use. The kernel allows it, but if programs touch that much the OOM killer steps in.

## Video pipeline

From `/proc/rkisp-vir0`:

- Sensor: JX-F37P (`jx_f37P` module), raw `SBGGR10_1X10`, 1920×1080 at 30 fps, through `rkcif-mipi-lvds`.
- ISP outputs: `rkisp_mainpath` and `rkisp_selfpath`, both NV12 1920×1080.
- 3D noise reduction (`BAY3D`) is on.
- The direct ISP-to-encoder mode is off (`ISP2ENC offline warp:0`), although its kernel module `rk_dvbm` is
  loaded.

## Allocations in the reserved area

Every allocation listed in `/proc/rk_dma_heap/dma_heap_info`, grouped. "Allocated by" is the allocator name the
kernel shows (`vmpi` is rockit, used by `lp_app`); "devices" are the hardware blocks the buffer is attached to.

| Use | Allocated by | Devices | Buffers | KiB |
|---|---|---|---|---|
| Frames from ISP to encoder, NV12 1920×1088 (3,060 KiB each) | `vmpi` | `rkvenc`, `rkisp` | 4 | 12,240 |
| Encoder working frames, 3,092 KiB each [INFERENCE: reference/reconstruction] | `vmpi` | `rkvenc` | 2 | 6,184 |
| Encoder small buffers: 508, 340, 2×128, 2×4 [INFERENCE: stream output, metadata] | `vmpi` | `rkvenc` | 6 | 1,112 |
| Other `vmpi` buffer | `vmpi` | none | 1 | 12 |
| ISP internal, 3,316 KiB [INFERENCE: noise-reduction history frame] | `rkisp` | none listed | 1 | 3,316 |
| ISP other: 256, 16, 2×4 | `rkisp` | none listed | 4 | 280 |
| Virtual ISP device, 4×16 | `rkisp-vir0` | none listed | 4 | 64 |
| **Total** | | | **22** | **23,208** |

`/proc/rk_cma/rk-dma-heap-cma` reports `Total: 24576 KiB`, `Used: 23208 KiB`. `/proc/meminfo` shows the same
area as `CmaTotal` 24,576 kB, `CmaAllocated` 23,208 kB, `CmaFree` 0 kB.

The 3,060 KiB frame size matches NV12 at 1920×1088 (1080 lines rounded up to a multiple of 16):
1920 × 1088 × 1.5 = 3,133,440 bytes = 3,060 KiB.

## Could it be smaller?

Shrinking the reserved area by itself does not help: `lp_app` asks for the same buffers and fails to start its
video. Memory could only be saved by changing the pipeline [INFERENCE: estimates from the table above]:

| Change | Saves | Cost |
|---|---|---|
| 3 frame buffers instead of 4 | about 3 MB | more risk of dropped frames |
| 2 frame buffers instead of 4 | about 6 MB | more risk of dropped frames |
| 3D noise reduction off | about 3.3 MB | noisier image, worst at night under IR |
| Lower resolution, e.g. 720p | more than half | lower image quality |
| Direct ISP-to-encoder mode | most of the 12 MB of frame buffers [INFERENCE] | none known; `lp_app` does not use it |

All of these are settings inside `lp_app`. No config file for them is known. The SDK test tools have such
options (for example `--buf_cnt` in [`rk_mpi_vi_dup_test`](cam-3.1.3/oem/usr/bin/rk_mpi_vi_dup_test.md) and
`--enc_buf_cnt` in [`rk_mpi_venc_test`](cam-3.1.3/oem/usr/bin/rk_mpi_venc_test.md)), but `lp_app` does not read
them. Even if the area were made smaller, the freed RAM would only help programs other than `lp_app`.

## Commands

All read-only:

```sh
cat /proc/meminfo
grep -i 'system ram' /proc/iomem
cat /proc/rk_memblock/memory /proc/rk_memblock/reserved
head -3 /proc/rk_cma/rk-dma-heap-cma          # the rest is an allocation bitmap
cat /proc/rk_dma_heap/dma_heap_info           # one block per buffer: size, allocator, devices
head -12 /proc/rkisp-vir0                     # sensor, ISP outputs, ISP2ENC mode
tr '\0' '\n' < /proc/device-tree/chosen/bootargs; cat /proc/cmdline
```
