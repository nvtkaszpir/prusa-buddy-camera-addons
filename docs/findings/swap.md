# Swap

Whether the camera can use swap (a swapfile on the microSD card, a swap partition, or zram) to get more memory
than its 34 MB. Checked on the maintainer's camera (firmware 3.1.3, kernel 5.10.110) on 2026-11-16, while
`lp_app` was running, and in the kernels of the 3.1.3 and 3.1.6 update packages.

## Summary

The kernel is built without swap support (`CONFIG_SWAP` off). No form of swap can work on the stock firmware:
not a swapfile on the card, not a dedicated swap partition, not zram. Swap support is part of the kernel core,
not a module, so it cannot be loaded later. The 3.1.6 kernel has no swap support either.

Getting swap would need a custom kernel; see [What it would take](#what-it-would-take).

## Evidence

On the camera:

- **`swapon(2)` is not implemented.** `swapon /dev/null` fails with `Function not implemented` (ENOSYS).
  `/dev/null` exists, so the error comes from the kernel, not from busybox checking the path first. A kernel
  with swap support would reject `/dev/null` with `Invalid argument` instead. The test activates nothing.
- **Kernel symbols.** In `/proc/kallsyms`, `sys_swapon` is a weak symbol (`W`), and `sys_ni_syscall` (the
  "not implemented" handler) exists. That is how the kernel marks a system call that is compiled out. The swap
  code itself (`try_to_unuse`, `si_swapinfo`) is missing.
- **No swap interfaces.** `/proc/swaps` does not exist, and `/sys/kernel/mm/` contains only `ksm` (a kernel with
  swap also has `swap/`). Both are created by the kernel's swap code.
- **`/proc/meminfo`:** `SwapTotal: 0 kB`, `SwapFree: 0 kB`. With `lp_app` running: `MemFree` 1,508 kB,
  `MemAvailable` 4,816 kB. `/proc/sys/vm/swappiness` (60) exists, but it is there even without swap support.
- **No zram.** `/sys/block` has only `mtdblock0`–`mtdblock8` and `mmcblk1`; there is no zram device and no
  `zram.ko` in `/oem/usr/ko/`. zram needs swap support anyway, to be used as swap.
- **The tools are there, the kernel is not.** The system busybox has `swapon`, `swapoff` and `fallocate`; the
  larger BusyBox installed as [`/oem/usr/sbin/udhcpd`](cam-3.1.3/oem/usr/sbin/udhcpd.md) also has `mkswap`.
  They only call into the kernel, so they cannot help.

In the update packages: the kernel in `boot.img` of `cam-3.1.3.tar` and `cam-3.1.6.tar` (xz-compressed zImage,
`Linux version 5.10.110`) contains none of the messages of the kernel's swap code (`mm/swapfile.c`), such as
`Unable to find swap-space signature` or `Adding %uk swap`, and no `zram` string.

## Commands

All read-only:

```sh
cat /proc/swaps                        # "No such file or directory" without swap support
grep -i swap /proc/meminfo
ls /sys/kernel/mm/                     # "swap" is listed only with swap support
swapon /dev/null                       # "Function not implemented" = no swap support
grep -E ' (sys_swapon|try_to_unuse|si_swapinfo|sys_ni_syscall)$' /proc/kallsyms
```

## What it would take

Not tried, and not recommended [INFERENCE]:

1. Build the Rockchip RV1106 SDK kernel (5.10.110) with `CONFIG_SWAP=y` (and optionally `CONFIG_ZRAM`), using
   the same configuration otherwise.
2. Rebuild every module in `/oem/usr/ko/` for that kernel, or make sure their version magic still matches.
3. Flash the new kernel to the boot partition (`mtd4`).

A failed flash can leave the camera unbootable, and the next firmware update replaces the kernel again. Even
with swap, the microSD card would be slow for paging and would wear, and it does not help the 24 MB CMA area
(contiguous memory for camera and encoder buffers), which cannot be swapped. See [Video](video.md) for the RAM
layout and [NPU](npu.md) for how full the CMA area is.
