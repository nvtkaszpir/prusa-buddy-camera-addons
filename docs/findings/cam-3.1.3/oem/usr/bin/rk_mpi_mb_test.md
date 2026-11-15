# `rk_mpi_mb_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_mb_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `13896` |
| sha256 | `c02e1d71bae49c771e9b49a37bfd100dfd5a878da8ec0d55b152486cbe85ae83` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_mb_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

This is a unit test for rockit's media-buffer (MB) pool allocator. It creates one or more MB pools of DMA buffers (IOMMU or CMA, cached or uncached) or of plain malloc buffers. It takes buffers from each pool and checks every handle-conversion API (physical/virtual address, fd, pool id, user count, unique id). It then releases everything and destroys the pools. It is an SDK self-test of the buffer subsystem that every rockit media module uses.

## Usage

The option table was rebuilt from the argparse table built in `main`. Defaults come from `main`'s stack-context initialisation: literal pool `(1, 4194304, 1, 1)` at ctx+0..15, `remap_mode` = 512, zeros elsewhere.

```
./rk_mpi_mb_test [-c MB_COUNT] [-s MB_SIZE]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-n` | `--loop` | int | the count of looping. default(1). | 1 |
| `-c` | `--mb_count` | int | the count of mb. default(1). | 1 |
| `-s` | `--mb_size` | int | mb size. default(4MB). | 4194304 |
| `-p` | `--pool_count` | int | the count of pool. default(1). | 1 |
| `-a` | `--pre_alloc` | int | pre alloc or not. default(0). 0: no 1: yes. | 0 |
| `-r` | `--remap_mode` | int | remapping mode. default(2). 0: none, 256: no cache, 512: cached | 512 (the help text's "default(2)" is wrong) |
| `-t` | `--alloc_type` | int | alloc type. default(0). 0: DMA, 1: malloc | 0 |
| `-d` | `--dma_type` | int | dma type. default(0). 0: IOMMU, 1: CMA | 0 |

## How it works

1. `main` parses the options and calls `RK_MPI_SYS_Init` ("rk mpi sys init fail!" on error). It then calls `unit_test_mpi_mb(ctx)` and prints "test running ok." or "test running failed!". Finally it calls `RK_MPI_SYS_Exit`.
2. `unit_test_mpi_mb` runs the following for each loop ("looping times %d"):
   - For `pool_count` pools it fills an `MB_POOL_CONFIG_S` (block size, count, pre-alloc, remap mode, alloc type, DMA type) and calls `RK_MPI_MB_CreatePool` ("pool id %d").
   - For each pool it calls `RK_MPI_MB_GetMB` `mb_count` times. For each block it:
     - gets `RK_MPI_MB_Handle2PhysAddr` and checks the address (the code checks for 4096-byte alignment when DMA is used);
     - checks that `RK_MPI_MB_Handle2PoolId` equals the pool id;
     - checks that `RK_MPI_MB_InquireUserCnt` returns 1;
     - checks that `RK_MPI_MB_Handle2VirAddr` is non-NULL;
     - for DMA buffers, checks that `RK_MPI_MB_Handle2Fd` returns fd ≥ 0, that `RK_MPI_MB_VirAddr2Handle(vaddr)` returns the same handle, and that `RK_MPI_MB_Handle2UniqueId` and then `RK_MPI_MB_UniqueId2Fd` give a duplicated fd, which is logged and then `close`d;
     - logs "get poolId(%d) from mb(%p) refsCount(%d) phyAddr(0x%llx) virAddr(%p) fd(%d) uniqueId(%d) dupFd(%d)";
     - keeps the handle in a `std::vector<void*>`.
   - A failed check calls `RK_MPI_MB_ReleaseMB` and fails the test.
   - Afterwards every handle is released with `RK_MPI_MB_ReleaseMB` and every pool destroyed with `RK_MPI_MB_DestroyPool`.

With the defaults this allocates one 4 MiB cached IOMMU DMA buffer.

## Interfaces touched

- Device nodes / sysfs / procfs: none named in the binary. librockit's allocator is reached through the rockit kernel module, and librockit.so contains `/dev/mpi/valloc` (likely the MB/DMA allocator node) and `/dev/ion` [INFERENCE]. `/dev/rk_dma_heap/` exists on the device. Uses dma-buf fds (`close` on the duplicated fd).
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_mb_test` matches only the binary itself. Running it temporarily takes DMA/CMA memory from the same pool as `lp_app`'s video pipeline. With large `-s`/`-c`/`-p` values on this small-RAM SoC it could make `lp_app` allocations fail or trigger the OOM killer while it runs [INFERENCE]. It has no persistent side effects.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_MB_{CreatePool,DestroyPool,GetMB,ReleaseMB,Handle2PhysAddr,Handle2VirAddr,Handle2Fd,Handle2PoolId,Handle2UniqueId,UniqueId2Fd,VirAddr2Handle,InquireUserCnt}`, `RK_MPI_SYS_{Init,Exit}`, `close`.
- Exported: `unit_test_mpi_mb(const _rkTestMbCtx*)`, `main`.
- Disassembly of `main`:
  ```
  11154 vldr d18/d19 ([pc] -> 1, 4194304, 1, 1) ; vstr d18,[sp,#8]; vstr d19,[sp,#16]  ; mb_count, mb_size, pool_count, loop
  11178 mov r3,#512 ; str r3,[sp,#32]              ; remap_mode default 512
  11374 bl RK_MPI_SYS_Init ; 11384 bl unit_test_mpi_mb
  ```
- `unit_test_mpi_mb` call order: `CreatePool` → `GetMB` → `Handle2PhysAddr` (`cmp r3,#4096`) → `Handle2PoolId` → `InquireUserCnt` (`cmp r0,#1`) → `Handle2VirAddr` → `Handle2Fd` → `VirAddr2Handle` → `Handle2UniqueId` → `UniqueId2Fd` → `RK_LOG` → `close` … `ReleaseMB` → `DestroyPool`.
- librockit.so strings: `/dev/mpi/valloc`, `/dev/ion`.

## Open questions

- The exact kernel node librockit uses for DMA allocation (`/dev/mpi/valloc` versus a dma-heap) is not determinable from this binary [INFERENCE].
- The precise meaning of the 4096 comparison on the physical address (alignment versus page-size check) was not traced fully.
