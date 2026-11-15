# NPU (neural processing unit)

Whether the camera's SoC has an NPU, and whether the firmware uses it. Checked read-only on the maintainer's camera
(firmware 3.1.3, 192.168.1.75) on 2026-11-14, while a print was running, plus the January 2026 firmware dump in
`firmware_images/scard-content-old/3/dump/`. The NPU driver was **not** loaded for this page.

## Summary

- The SoC (Rockchip RV1103G) has an NPU, and the device tree enables it (`status = "okay"`). Rockchip gives about
  0.5 TOPS for the RV1103 NPU [INFERENCE: datasheet figure, not measured].
- The firmware ships the kernel driver `rknpu.ko` (0.8.2) and the runtime library `librknnmrt.so` (1.4.1b9), but
  the driver is never loaded: its line in `/oem/usr/ko/insmod_ko.sh` is commented out. There is no `/dev/rknpu`.
- Nothing on the camera uses the NPU. `lp_app` (3.1.0 and 3.1.3) and the tools in `/oem/usr/bin` do not reference
  `rknn`. The driver and library are SDK leftovers.
- While `lp_app` runs there is no memory for it: the 24 MB CMA area (contiguous memory for camera, ISP, encoder
  and NPU buffers) had 0 KB free.

## Evidence

Hardware (device tree in `/proc/device-tree`, sysfs):

- **SoC**: `compatible` = `rockchip,rv1103g-evb-v10`, `rockchip,rv1103`.
- **NPU node**: `npu@ff660000`, `compatible = "rockchip,rv1106-rknpu"`, `status = "okay"`.
- **Registers**: `0xff660000`, size `0x10000` (64 KB). **Interrupt**: GIC SPI 109 (`0x6d`), level high.
- **Clocks**: `aclk`, `hclk`; `assigned-clock-rates` 420 MHz (`0x1908b100`).
- **Platform device**: `/sys/bus/platform/devices/ff660000.npu` exists, but has **no driver bound** (no
  `driver` link).

Software:

- **Kernel driver**: `/oem/usr/ko/rknpu.ko`, 37,928 bytes. `modinfo` (on the dump copy): "RKNPU driver",
  version 0.8.2, author Felix Zeng (Rockchip), GPL v2, vermagic `5.10.110 mod_unload ARMv7 thumb2 p2v8`, which
  matches the camera's kernel 5.10.110.
- **Not loaded**: `lsmod` and `/proc/modules` do not list it; there is no `/dev/rknpu`, no
  `/sys/kernel/debug/rknpu` and no NPU line in `dmesg`. The reason is line 40 of `/oem/usr/ko/insmod_ko.sh`,
  `#__insmod rknpu.ko`, commented out; the lines around it load `mpp_vcodec.ko` and `snd-soc-rv1106.ko`.
- **Runtime library**: `/oem/usr/lib/librknnmrt.so`, 141,048 bytes,
  `librknnmrt version: 1.4.1b9 (09eb4be80@2022-10-19T09:51:39)`. It checks the driver version at run time.
- **Users**: no `rknn` reference in the live 3.1.3 `lp_app` or in `/oem/usr/bin/*` (`grep`).
- **Live vs dump**: `rknpu.ko` (md5 `1fd869ff71b47aea5ace87bfde5cadba`) and `librknnmrt.so`
  (md5 `c696d0986bff75a1357f1f8331159621`) are identical on the camera and in the dump.
- **Memory** (`/proc/meminfo`, `lp_app` running): `MemTotal` 34,328 kB; `CmaTotal` 24,576 kB,
  `CmaAllocated` 23,208 kB, `CmaFree` 0 kB.

The node is named `rv1106-rknpu`: the RV1103 and RV1106 share the NPU block and the SDK [INFERENCE: from the
compatible string and the shared SDK]. See [Video](video.md) for the rest of the hardware (RAM layout,
video encoder).

## Commands

All read-only:

```sh
tr '\0' ' ' < /proc/device-tree/compatible; echo
ls /proc/device-tree/npu@ff660000/
cat /proc/device-tree/npu@ff660000/status
ls /sys/bus/platform/devices/ff660000.npu/      # a "driver" entry appears once rknpu.ko is bound
lsmod; ls -l /dev | grep -i npu
grep -n rknpu /oem/usr/ko/insmod_ko.sh
grep -i cma /proc/meminfo
```

## Using it

Not tried. What it would take [INFERENCE]:

1. Load the driver: `insmod /oem/usr/ko/rknpu.ko`. It probes `ff660000.npu`; `/dev/rknpu` (or a DRM node,
   depending on the driver build) should then appear, and the driver logs its version to `dmesg`.
2. Free memory. The driver allocates its buffers at probe and every model needs DMA memory for weights and
   tensors, but the CMA area is full while `lp_app` runs. So `lp_app` (and with it video, timelapse and Prusa
   Connect) would have to be stopped, or the model has to be tiny.
3. Convert a model to the RKNN format with an RKNN toolkit version whose output `librknnmrt` 1.4.1 accepts, and
   build a program for ARMv7 uClibc (the camera's C library) or ship its own loader, as the rsyslog add-on does
   with musl.

!!! warning "Test loading the driver only with the printer idle"
    If `rknpu.ko` fails during its probe, or does not unload cleanly with `rmmod`, only a reboot brings the
    camera back to a known state, and its buffer allocations compete with `lp_app` for the little free memory.
    Do the load test with no print running, preferably with `lp_app` stopped.

## Open questions

- Whether `rknpu.ko` 0.8.2 probes cleanly on this board and which device node it creates.
- How much memory the driver needs at probe, and whether a small model fits next to `lp_app`.
- Which RKNN toolkit versions produce models that `librknnmrt` 1.4.1b9 loads.
