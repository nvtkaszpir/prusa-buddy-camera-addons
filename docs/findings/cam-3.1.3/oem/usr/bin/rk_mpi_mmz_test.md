# `rk_mpi_mmz_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_mmz_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `13888` |
| sha256 | `b85c1a83b2782e7d5166ed9a30233a478da332523e006bed4628daa9eb897832` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_mmz_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

This is a fixed-sequence unit test for rockit's MMZ ("media memory zone") API, the simple DMA-buffer allocator in `rk_mpi_mmz.h`. It allocates one 1 MiB DMA buffer, prints its fd, length, physical address, virtual address and cacheability, and tests the reverse lookups (fd, virtual address or physical address back to handle, including off-by-one and out-of-range addresses). It then exercises the cache-flush API variants and frees the buffer. It takes no meaningful options.

## Usage

The argparse table here is a static `.data` array (0x2718) holding only the `help` entry and the "basic options:" group. The usage string is stale: the `-c`/`-s` options it mentions do not exist in this binary.

```
./rk_mpi_mmz_test [-c MB_COUNT] [-s MB_SIZE]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |

Running it without arguments executes the whole test.

## How it works

The test body (`unit_test_mpi_mmz`) is inlined into `main`. Note that `RK_MPI_SYS_Init` is not called; the MMZ API is used standalone.

1. `RK_MPI_MMZ_Alloc(&mb, 1048576, 1)` allocates 1 MiB with flags = 1. In the public `rk_mpi_mmz.h` that flag selects CMA, cacheable [INFERENCE: header values not in the binary]. On failure it logs "alloc mmz fail".
2. Query: `RK_MPI_MMZ_Handle2VirAddr`, `Handle2PhysAddr`, `Handle2Fd`, `GetSize`, `IsCacheable` → "alloc buffer: fd=%d, len=%d, paddr=0x%x, vaddr=%p, cacheable=%d".
3. Reverse lookups:
   - `RK_MPI_MMZ_Fd2Handle(fd)` and `RK_MPI_MMZ_VirAddr2Handle(vaddr)` → "MB: %p %p %p".
   - `VirAddr2Handle` for vaddr+1, vaddr-1, vaddr+len and vaddr+len-1 ("vaddr+1: %p, mb: %p", …).
   - `RK_MPI_MMZ_PhyAddr2Handle` for paddr±1, paddr+len and paddr+len-1.
   - For vaddr+len-10 and paddr+len-10 it gets the handle, then `Handle2VirAddr`/`Handle2PhysAddr` and `Handle2Fd`, and logs the offset inside the buffer ("vaddr+len-10: %p, fd: %d, offset: %d").
4. Cache maintenance:
   - `RK_MPI_MMZ_FlushCacheStart(mb, 0, 0, 1)`, then `memset(vaddr, 0x5A, len)`, then `RK_MPI_MMZ_FlushCacheEnd(mb, 0, 0, 1)`.
   - The same with offset 4096, length 4096 and flag 2.
   - `RK_MPI_MMZ_FlushCacheVaddrStart/End(vaddr+len-10, 4096, 1)` around 8-byte stores.
   - `RK_MPI_MMZ_FlushCachePaddrStart/End(paddr+len-10, 4096, 1)` around the same stores.
   - The last argument is presumably the sync direction (1 = read-only, 2 = write-only) [INFERENCE: header values].
5. `usleep(100000)`, then `RK_MPI_MMZ_Free(mb)` → "test running ok." Any failure → "test running failed!".

## Interfaces touched

- Device nodes / sysfs / procfs: none named in the binary. The allocation goes through librockit to the kernel DMA allocator; librockit.so contains `/dev/mpi/valloc` and `/dev/ion`, and the device has `/dev/rk_dma_heap/` [INFERENCE about which one is used].
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_mmz_test` matches only the binary itself. It briefly allocates 1 MiB of DMA/CMA memory and writes a test pattern into its own buffer. It can coexist with `lp_app` unless CMA is exhausted, and it has no persistent side effects.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_MMZ_{Alloc,Free,GetSize,IsCacheable,Handle2Fd,Handle2PhysAddr,Handle2VirAddr,Fd2Handle,VirAddr2Handle,PhyAddr2Handle,FlushCacheStart,FlushCacheEnd,FlushCacheVaddrStart,FlushCacheVaddrEnd,FlushCachePaddrStart,FlushCachePaddrEnd}`, `usleep`. No `RK_MPI_SYS_Init`.
- Exported: `unit_test_mpi_mmz(const _rkTestMMZCtx*)` (string), `main`.
- Disassembly of `main`:
  ```
  110f4 mov r2,#1 ; mov r1,#1048576 ; add r0,sp,#76 ; bl RK_MPI_MMZ_Alloc
  114bc mov r2,#0 ; mov r1,r2 ; mov r3,#1 ; bl RK_MPI_MMZ_FlushCacheStart
  114d8 mov r1,#90 ; bl memset
  114f8 mov r2,#4096 ; mov r1,r2 ; mov r3,#2 ; bl RK_MPI_MMZ_FlushCacheStart
  1159c movw r0,#34464 ; movt r0,#1 (=100000) ; bl usleep ; bl RK_MPI_MMZ_Free
  ```
- Static argparse table found in the file at offset 0x2718: `{type 2, "help", "show this help message and exit"}`.

## Open questions

- The numeric values of the `RK_MMZ_ALLOC_*` and sync flags come from the public header, not from the binary [INFERENCE].
- Which kernel allocator node backs MMZ on this firmware is not determinable statically from this binary.
