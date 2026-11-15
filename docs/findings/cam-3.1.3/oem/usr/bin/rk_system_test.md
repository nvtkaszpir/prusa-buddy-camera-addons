# `rk_system_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_system_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30156` |
| sha256 | `bddc5ad45934f6dc0d477ad60c9999ee9110bd34e5841cddb1cf7552c693ec0c` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A one-shot test program for the system-level `librksysutils` helpers. It runs three steps:

1. Prints the chip ID taken from the `Serial` line of `/proc/cpuinfo`.
2. Writes a 256-byte record holding `"rockchip"` to Rockchip vendor storage item ID 0 through `/dev/vendor_storage`, reads it back and prints it.
3. Suspends the system by writing `freeze` (suspend-to-idle) to `/sys/power/state`.

## Usage

None found. There are no options or help text, and `main` ignores `argc`/`argv`. Output strings:

```
chipid : %s
rk_chip_id_get fail!
VENDOR_WRITE fail
VENDOR_READ fail
Vendor read data : %s
```

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF698. Main is at 0x10f54.

1. `rk_chip_id_get(buf)` (lib 0x4994): `fopen("/proc/cpuinfo")` and `fgets` until a line contains `Serial`. It then takes the text after `:` (`strchr(':')`) and copies up to 64 bytes (`strncpy`). Errors print `Failed to open /proc/cpuinfo` or `Get chipid fail`. Main prints `chipid : %s`.
2. `rk_vendor_write(0, "rockchip"+zero padding, 256)` (lib 0x4cb4):
   - Rejects sizes over 1024 (`vendor storage input data overflow`).
   - `open("/dev/vendor_storage", O_RDWR)` (`vendor storage open fail`).
   - Builds a request `{tag = 0x56524551 "VREQ", id = 0, len = 256, data}`.
   - `ioctl(fd, VENDOR_WRITE_IO 0x40047602)` (`vendor write error`).
   - On failure main prints `VENDOR_WRITE fail`.
3. `rk_vendor_read(0, buf, 256)` (lib 0x4afc): `open(O_RDONLY)`, request `{VREQ, id 0, len 1024}`, `ioctl(VENDOR_READ_IO 0x40047601)`, then copies the data. Errors print `vendor read error %d` or `vendor storage: param size is lower then read size %d`. Main prints `Vendor read data : %s` or `VENDOR_READ fail`.
4. `rk_system_suspend(0)` (lib 0x4e90): opens `/sys/power/state` for writing:
   - type 0 → `fprintf("freeze")`.
   - type 1 → writes `s2idle` to `/sys/power/mem_sleep`, then `mem` to state.
   - any other type → `input SUSPEND_TYPE error`.
   This program passes 0, so it requests suspend-to-idle. The write blocks until the system resumes. Main then returns 0.

The library also contains `rk_system_reboot` (`system("reboot")`) and `rk_system_shutdown` (`system("halt")`), but this main never calls them.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/proc/cpuinfo` (read)
  - `/dev/vendor_storage` (open RDWR for the write, RDONLY for the read; ioctls 0x40047602 / 0x40047601)
  - `/sys/power/state` (writes `freeze`)
- Files and paths read/written: vendor storage item ID 0 is persistently overwritten. That storage lives in a reserved area of flash or EMMC. [INFERENCE about backing store]
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_system_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`). `lp_app` has no `vendor_storage` or `rk_vendor_*` strings.
- **Side effects:**
  - **Persistent flash write:** item ID 0 of the Rockchip vendor storage is overwritten with `"rockchip"` and 248 zero bytes. Commonly documented IDs 1–4 hold the serial number and Wi-Fi/LAN/BT MACs; ID 0 does not normally carry those, but vendor-specific use by Prusa/the ODM cannot be ruled out. [INFERENCE]
  - **System suspend:** writing `freeze` to `/sys/power/state` puts the camera into suspend-to-idle. Userspace (lp_app streaming) and Wi-Fi stop until a wakeup source fires; possibly the device never wakes without a power cycle. [INFERENCE]
- The dumped `/dev/char/` has no misc entry pointing at `vendor_storage`, so on this unit the vendor write and read may simply fail (`vendor storage open fail`). In that case only the chip-ID print and the suspend take effect. [INFERENCE]

## Evidence

```
$ readelf -d rk_system_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_system_test
   5750 rk_chip_id_get fail!
   5768 chipid : %s
   5774 VENDOR_WRITE fail
   5788 VENDOR_READ fail
   579c Vendor read data : %s
   57b4 rockchip
   ... /proc/cpuinfo, Serial, /dev/vendor_storage, /sys/power/state, freeze, /sys/power/mem_sleep, s2idle (library)
```
Main excerpt:
```
10fa8: bl 0x1402c                         ; rk_chip_id_get(buf)
10fe8: "rockchip" -> buf[256] (memset rest 0)
11030: mov r2,#256 ; mov r0,#0 ; bl 0x1434c ; rk_vendor_write(0, buf, 256)
11060: mov r2,#256 ; mov r0,#0 ; bl 0x14194 ; rk_vendor_read(0, out, 256)
110a8: mov r0,#0 ; bl 0x14528              ; rk_system_suspend(0)
```
Library:
```
4b9c: movw/movt r3,#0x56524551 ("VREQ") ; 4bc8: ioctl 0x40047601 (read)
4dbc: ioctl 0x40047602 (write) ; 4d20: open(..., O_RDWR)
4f28: cmp type,#0 ; beq -> "freeze" written to /sys/power/state
```

## Open questions

- Whether `/dev/vendor_storage` exists in the running kernel, and whether vendor ID 0 holds anything important on this product.
- Which wakeup sources are enabled for suspend-to-idle on this board (for example the RTC alarm, the adc-keys button or Wi-Fi), i.e. whether the camera would resume by itself.
