# `rk_adc_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_adc_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30156` |
| sha256 | `69cf7b73eeb41c26bd8e86ae61dd3e9116992c5ca7412445f214bfa3e4dd985d` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A one-shot test program for the SAR-ADC. It looks up the IIO device whose `name` is `ff5e0000.saradc` (hard-coded), prints its index, reads raw channels 0–4 (`in_voltage0_raw`…`in_voltage4_raw`) and prints them on one line, then exits. It only reads. On this camera the only IIO device is `iio:device0` named `ff3c0000.saradc` (verified read-only on the live camera, 2026-10-31), so the name lookup fails and the tool cannot read the ADC channels as shipped.

## Usage

None found. There are no options or help text, and `main` ignores `argc`/`argv`. Output format:

```
rk_adc_get_devnum %d
rk_adc_get_value %d, %d, %d, %d, %d
```

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF650. Main is at 0x10f54.

1. `rk_adc_get_devnum("ff5e0000.saradc")` (lib 0x1f14) calls `iio_find_type_by_name(name, "iio:device")`. That does `opendir("/sys/bus/iio/devices/")`, walks the `iio:deviceN` entries, reads `%s%s%d/name` and compares it. It returns N, or prints `No industrialio devices available`, `failed to read element number` etc.
2. It prints `rk_adc_get_devnum %d`.
3. For channel = 0..4 it calls `rk_adc_get_value(devnum, ch)` (lib 0x1f4c), redoing the devnum lookup each time. That builds `/sys/bus/iio/devices//iio:device<N>` (format `%s/%s%d`, which gives a harmless double slash) plus `in_voltage<ch>_raw`, and calls `read_sysfs_posint` (`fopen`/`fscanf("%d")`).
4. It prints `rk_adc_get_value %d, %d, %d, %d, %d` and returns 0. Channels that don't exist read as an error code (negative). [INFERENCE: read_sysfs_posint returns -errno]

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/bus/iio/devices/` (directory scan), `/sys/bus/iio/devices/iio:deviceN/name`, `/sys/bus/iio/devices/iio:deviceN/in_voltage{0..4}_raw` (read-only).
- Files and paths read/written: none other than the sysfs reads.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_adc_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- The SAR-ADC exists, but under a different name than the tool expects. Verified read-only on the live camera, 2026-10-31: the only IIO device is `iio:device0` with `name` = `ff3c0000.saradc`; the binary hard-codes `ff5e0000.saradc`. `iio_find_type_by_name` therefore finds no match, and `rk_adc_get_devnum` takes its failure path. Expected observable result: `rk_adc_get_devnum` prints a negative (error) value, and every `rk_adc_get_value` repeats the failed lookup, so all five values are errors instead of ADC readings. [INFERENCE: the exact return value and any extra error message on a name mismatch are not documented]
- Live readings for context (same check, daytime): `in_voltage0_raw` = 1023, `in_voltage1_raw` = 467 (light-sensor channel); channels 2/3 were not readable.
- `lp_app` reads the same ADC itself: strings `/sys/bus/iio/devices/iio:device0/in_voltage%d_raw`, `getAdc`, `ldr adc: %d, vout: %f`, `lp_rv1106_adc.cpp`. It uses an ADC channel for the ambient-light sensor (LDR) that drives day/night switching; the live check identifies it as channel 1. lp_app opens `iio:device0` directly by index, so the name mismatch does not affect it. The adc-keys button also sits on the SAR-ADC. [INFERENCE: which channel the button uses]
- Reads only. It is safe to run alongside lp_app (no state changes, no side effects), but as shipped it is useless on this unit because of the device-name mismatch.

## Evidence

```
$ readelf -d rk_adc_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_adc_test
   5708 ff5e0000.saradc
   5718 rk_adc_get_devnum %d
   5730 rk_adc_get_value %d, %d, %d, %d, %d
   ... /sys/bus/iio/devices/, iio:device, %s/%s%d, in_voltage%d_raw (library)
$ strings oem/usr/sbin/lp_app | grep iio  -> /sys/bus/iio/devices/iio:device0/in_voltage%d_raw
```
Main excerpt:
```
10f74: bl 0x11564 ; rk_adc_get_devnum("ff5e0000.saradc") ; printf("rk_adc_get_devnum %d")
10fa4: mov r1,#0 ; bl 0x1159c ; rk_adc_get_value(dev, 0)
10fc8: mov r1,#1 ...  10fec: mov r1,#2 ...  11010: mov r1,#3 ...  11034: mov r1,#4
11060: bl printf("rk_adc_get_value %d, %d, %d, %d, %d")
```
Library `rk_adc_get_value`: `sprintf("%s/%s%d", "/sys/bus/iio/devices/", "iio:device", n)`, `sprintf("in_voltage%d_raw", ch)`, `bl read_sysfs_posint`.

## Open questions

- ~~Which SAR-ADC channel carries the light sensor~~: the live check (2026-10-31) shows channel 1 = 467 in daytime, matching the light-sensor channel; channel 0 reads 1023 (full scale). Which channel the adc-keys button uses is still open (needs the device tree).
- How many channels the SAR-ADC driver exposes: the live check read channels 0 and 1, while channels 2/3 were not readable, so only 0 and 1 appear to be exposed. Moot for this tool, which fails the device-name lookup first.
- Exact output of `rk_adc_test` on the name mismatch (return value of `iio_find_type_by_name` when no device matches) has not been confirmed.
