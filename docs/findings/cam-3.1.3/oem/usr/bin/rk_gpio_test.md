# `rk_gpio_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_gpio_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30160` |
| sha256 | `53f0c5730a737a06bad457f77225af9a73881e2eac71356861bc218a1f2574c5` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A test program for sysfs GPIO. It exports GPIO 142 as an input and GPIO 38 as an output, drives GPIO 38 low, and then copies the level of GPIO 142 to GPIO 38 every 20 ms, forever. It has no output and no exit path. These hard-coded pin numbers suit an SDK reference board, not necessarily this camera.

## Usage

None found. The program has no options, no help text and no app-specific strings; `main` ignores `argc`/`argv`. It runs until killed:

```
rk_gpio_test        # no arguments; loops forever, silent unless a library call prints an error
```

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF5B0 from `librksysutils.so`. Main is at 0x10f88 and is only 26 instructions.

1. `rk_gpio_export_direction(142, 1)` (lib 0x3078). This calls `rk_gpio_export`, which writes `142` to `/sys/class/gpio/export`. If `/sys/class/gpio/gpio142` already exists it prints `warning: gpio %d, file (%s) has exist` and continues. It then calls `rk_gpio_set_direction(142, 1)`, which writes `in` to `/sys/class/gpio/gpio142/direction` (the bool argument maps nonzero→`in`, 0→`out`). It unexports again if that fails.
2. `rk_gpio_export_direction(38, 0)`: export GPIO 38 and set direction to `out`.
3. `rk_gpio_set_value(38, 0)`. `rk_gpio_set_value` reads `direction` first and only writes `value` when it is `out` (`write_sysfs_int_and_verify`).
4. Endless loop: `usleep(20000)`; `v = rk_gpio_get_value(142)` (`read_sysfs_posint` of `/sys/class/gpio/gpio142/value`); `rk_gpio_set_value(38, v)`.

There is no `rk_gpio_unexport` and no return. The GPIOs stay exported and GPIO 38 keeps its last level after the process is killed.

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/class/gpio/export`; `/sys/class/gpio/gpio142/{direction,value}`; `/sys/class/gpio/gpio38/{direction,value}`. `unexport` is present in the library code but this main never calls it.
- Files and paths read/written: the sysfs files above only.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_gpio_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- **Side effects:** it forces GPIO 38 to output and keeps driving it, and it reconfigures GPIO 142 as an input. With Rockchip numbering (bank×32 + group×8 + index), 142 = GPIO4_B6 and 38 = GPIO1_A6 [INFERENCE]. What those pins do on the Buddy3D board is unknown.
- `lp_app` (`/oem/usr/sbin/lp_app`) does its own sysfs GPIO handling (strings `/sys/class/gpio/export`, `/sys/class/gpio/gpio%d/direction`, `.../value`, `lp_peri_sys_gpio.cpp`). It drives GPIO 54 (SPI motor-driver enable), GPIO 55 (IR LED / IR-cut related), GPIO 56 (status LED), the IR LED PWM on `pwmchip8` (`pwmchip7` on boards with a UART), and pulses the IR-cut filter through the SPI motor driver; see [lp_app.md](../sbin/lp_app.md). It does not use GPIO 38 or 142, so this program is not expected to conflict with lp_app's IR control. What GPIO 38/142 are wired to on this board remains unknown; the library only warns when a GPIO is already exported and then re-sets the direction anyway, so if some other component used them it would be overridden. [INFERENCE]
- No flash writes and no reboot.

## Evidence

```
$ readelf -d rk_gpio_test | grep NEEDED  -> [libc.so.0]
$ strings rk_gpio_test   -> no app-specific strings; only the statically linked librksysutils strings
   (/sys/class/gpio, %s/gpio%d, export, unexport, direction, value, ...)
```
Main (annotated `llvm-objdump`):
```
10f9c: mov r3,#142 ; 10fa4: mov r3,#38
10fac: mov r1,#1 ; ldr r0,=142 ; bl 0x12628   ; rk_gpio_export_direction(142, in)
10fb8: mov r1,#0 ; ldr r0,=38  ; bl 0x12628   ; rk_gpio_export_direction(38, out)
10fc4: mov r1,#0 ; ldr r0,=38  ; bl 0x126a0   ; rk_gpio_set_value(38, 0)
10fd0: movw r0,#20000 ; bl usleep
10fdc: bl 0x127cc                              ; rk_gpio_get_value(142)
10fec: bl 0x126a0                              ; rk_gpio_set_value(38, v)
10ff0: b 0x10fd0
```
Library `rk_gpio_set_direction` (0x2f08): `cmp r3,#0 ; beq -> "out" ; else "in"`, then `write_sysfs_string_and_verify("direction", "/sys/class/gpio/gpio%d")`.

## Open questions

- What GPIO 142 and GPIO 38 are wired to on this board (needs the device tree or schematic). The dump has `gpiochip0..3` only, so it is unclear whether bank 4 (GPIO 128–159) is even registered; if not, exporting 142 fails. [INFERENCE]
- Whether any component other than lp_app uses GPIO 38 or 142 (lp_app uses GPIO 54/55/56, see [lp_app.md](../sbin/lp_app.md)).
