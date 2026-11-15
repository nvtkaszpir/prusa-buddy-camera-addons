# `rk_led_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_led_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30156` |
| sha256 | `3ca26a8e4b8b92c982628b043de580681f25d6fd4e5a110bba70b00a2929ef42` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A one-shot test program for the LED class. It calls `rk_led_set_mode("white", 1, 255)`, which writes `255` to `/sys/class/leds/white/brightness` and then `timer` to `/sys/class/leds/white/trigger`. That leaves an LED named `white` blinking after the program exits.

## Usage

None found. There are no options, help text or stdin handling, and `main` ignores `argc`/`argv`. The only app-specific string is the LED name `white`. Library error messages can appear:

```
warning: /sys/class/leds is not exit
switch led fail
controll blink fail
```

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF550. Main is at 0x10f54 and makes one call:

`rk_led_set_mode("white", /*blink*/ 1, /*brightness*/ 255)` (lib 0x3294):

1. `access("/sys/class/leds", F_OK)`. If that fails it prints `warning: /sys/class/leds is not exit` and returns -1.
2. `sprintf(path, "%s/%s", "/sys/class/leds", "white")`.
3. `write_sysfs_int("brightness", path, 255)` (`switch led fail` on error).
4. If brightness != 0: `write_sysfs_string("trigger", path, blink ? "timer" : "none")`; here that is `timer` (`controll blink fail` on error). If not blinking, it writes `brightness` again.
5. Main returns 0. Nothing is restored.

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/class/leds` (access check), `/sys/class/leds/white/brightness` (write `255`), `/sys/class/leds/white/trigger` (write `timer`).
- Files and paths read/written: the sysfs files above only.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_led_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- `lp_app` has no `/sys/class/leds` string; it drives its peripherals through GPIO and PWM sysfs. Whether this board defines an LED-class device called `white` is unknown. If it doesn't, the write fails with `failed to open ...` / `switch led fail` and nothing happens. [INFERENCE]
- **Side effect:** if a `white` LED exists, it is left blinking with the kernel `timer` trigger (default delays, typically 500 ms on/off) until something writes `none` to `trigger`. If that LED is a white illuminator, the visible light will flicker in the image. [INFERENCE]
- No flash writes and no reboot.

## Evidence

```
$ readelf -d rk_led_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_led_test | grep -E 'white|leds|trigger|timer|brightness'
   5608 white
   ... /sys/class/leds, brightness, timer, none, trigger (library)
```
Main (complete):
```
10f68: mov r2,#255
10f6c: mov r1,#1
10f70: ldr r3,=…  add r3,pc,r3   ; "white"
10f7c: bl 0x127e4                ; rk_led_set_mode("white", 1, 255)
10f80: mov r3,#0 ; return 0
```
Library `rk_led_set_mode`:
```
3358: bl write_sysfs_int("brightness", "/sys/class/leds/white", 255)
3390: ldrb r3,[blink] ; cmp #0 ; "timer" : "none"
33cc: bl write_sysfs_string("trigger", path, mode)
```

## Open questions

- Whether `/sys/class/leds/white` exists on this camera (sysfs is not in the dump). Possibly an SDK reference-board name only.
