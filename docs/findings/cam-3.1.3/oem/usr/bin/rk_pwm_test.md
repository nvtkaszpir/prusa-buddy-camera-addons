# `rk_pwm_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_pwm_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30164` |
| sha256 | `4c3a835433ecf0a3ff290cc88d7b90cb0183271127dbde0984bd8b259d761351` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A test program for sysfs PWM combined with GPIO. It sets up GPIO 142 as an input, GPIO 38 as an output (driven low), and `pwmchip2/pwm0` with a 62500 ns period (16 kHz) at 50 % duty and normal polarity. After each line read from stdin, it copies the GPIO 142 level to GPIO 38 and turns PWM2 on or off to match. When the level changes it prints a status block.

## Usage

There are no command-line options: `main` ignores `argc`/`argv`. It prints:

```
#Usage: input 'quit' to exit programe!
```

Despite that message, the binary never checks for `quit`: main has no `strstr` call and the loop flag is never cleared. Each line on stdin (any content) triggers one poll iteration, so the only way out is a signal (Ctrl-C/kill). When the input GPIO changes it prints:

```
[TEST_INFO]
-- in_gpio: in %d, value %d
-- out_gpio: in %d, value %d
-- pwm: period %d, duty %d, polartiy %d, enable %d
```

The `in %d` fields are the `rk_gpio_get_direction()` result.

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF728. Main is at 0x10fa8.

1. `rk_gpio_export_direction(142, 1)` exports GPIO 142 and writes `in` to its direction. `rk_gpio_export_direction(38, 0)` exports GPIO 38 as `out`. `rk_gpio_set_value(38, 0)` drives it low. The library code is the same as in `rk_gpio_test`.
2. `rk_pwm_init(2, 62500, 31250, 0)` (lib 0x3a74):
   - `rk_pwm_export(2)` writes `0` to `/sys/class/pwm/pwmchip2/export`. If `pwmchip2/pwm0` already exists it prints `warning: pwm %d, file (%s) has exist` and continues.
   - It then writes `period`=62500, `duty_cycle`=31250, and `polarity`=`normal` (0→`normal`, nonzero→`inversed`) under `/sys/class/pwm/pwmchip2/pwm0/`. If that fails it unexports again.
   - `enable` is not written here.
3. `puts("#Usage: ...")`.
4. Endless loop:
   - `fgets(stdin, 64)` (blocks until a line arrives), then `usleep(20000)`.
   - `v = rk_gpio_get_value(142)`. If `v` differs from the previous value: `rk_gpio_set_value(38, v)` and `rk_pwm_set_enable(2, v != 0)` (writes `/sys/class/pwm/pwmchip2/pwm0/enable`, verified).
   - It then reads back both GPIO directions and values plus `rk_pwm_get_period/duty/polarity/enable(2)` and prints the `[TEST_INFO]` block.
   - The "previous value" variable is never initialised, so whether the first iteration triggers is undefined.
5. Cleanup code exists after the loop (`rk_gpio_unexport(142)`, `rk_gpio_unexport(38)`, `rk_pwm_deinit(2)`, which writes `0` to `pwmchip2/unexport`), but the loop never ends normally, so it is unreachable. Killing the process leaves the GPIOs and PWM exported in their last state.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/sys/class/gpio/export`, `/sys/class/gpio/gpio142/{direction,value}`, `/sys/class/gpio/gpio38/{direction,value}`. `unexport` is in unreachable code.
  - `/sys/class/pwm/pwmchip2/export`, `/sys/class/pwm/pwmchip2/pwm0/{period,duty_cycle,polarity,enable}`. `unexport` is in unreachable code.
- Files and paths read/written: the sysfs files above only.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_pwm_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- **Side effects:**
  - It reprograms `pwmchip2` to 16 kHz / 50 % and switches its output on or off following GPIO 142.
  - It forces GPIO 38 to output.
  - `lp_app` drives PWM and GPIO through sysfs itself (strings `/sys/class/pwm/pwmchip%d/pwm0/{period,duty_cycle,enable}`, `lp_rv1106_pwm.cpp`, `export_pwm`, `init_irled`). Its IR LED PWM is `pwmchip8/pwm0` (or `pwmchip7` on boards with a UART), its IR GPIOs are 54/55 (plus GPIO 56 for the status LED), and the IR-cut filter is pulsed through the SPI motor driver; see [lp_app.md](../sbin/lp_app.md). It does not use `pwmchip2`, GPIO 38 or GPIO 142, so this test is not expected to conflict with lp_app's IR control. What `pwmchip2` and GPIO 38/142 are wired to on this board is unknown. [INFERENCE: these look like SDK reference-board pins]
- Note: `pwmchipN` numbering in sysfs follows probe order, so `pwmchip2` is not necessarily the SoC's PWM2 channel. [INFERENCE]
- No flash writes and no reboot.

## Evidence

```
$ readelf -d rk_pwm_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_pwm_test
   57e1 #Usage: input 'quit' to exit programe!
   5808 [TEST_INFO]
   5814 -- in_gpio: in %d, value %d
   5830 -- out_gpio: in %d, value %d
   584d -- pwm: period %d, duty %d, polartiy %d, enable %d
   (no "quit"/"#Get 'quit' cmd!" strings in this binary)
$ strings oem/usr/sbin/lp_app | grep pwm  -> /sys/class/pwm/pwmchip%d/pwm0/period ... export_pwm
```
Main excerpt:
```
10fe4: bl 0x127a0 ; rk_gpio_export_direction(142, 1)
10ff0: bl 0x127a0 ; rk_gpio_export_direction(38, 0)
10ffc: bl 0x12818 ; rk_gpio_set_value(38, 0)
11000: mov r3,#0 ; movw r2,#31250 ; movw r1,#62500 ; mov r0,#2 ; bl 0x1319c  ; rk_pwm_init(2,62500,31250,0)
11040: bl fgets ; 11048: bl usleep(20000) ; 11050: bl rk_gpio_get_value(142)
11078: bl rk_gpio_set_value(38, v) ; 11098: bl 0x130a0 ; rk_pwm_set_enable(2, v!=0)
110d0..110f4: rk_pwm_get_period/duty/polarity/enable(2) ; 11124: printf("[TEST_INFO]...")
11128: ldrb r3,[r11,#-41] ; cmp r3,#0 ; bne loop     ; flag set to 1, never cleared
```
Library: `3550: "export" via write_sysfs_int(…, "%s/pwmchip%d", 0)`; `3b14 "period"`, `3b40 "duty_cycle"`, `3b5c: cmp #0 -> "normal" else "inversed"`, `39d4 "enable"`.

## Open questions

- Which physical PWM channel and function `pwmchip2` is on this board, and what GPIO 38 and 142 are wired to. Needs the device tree. (lp_app does not use them; it uses `pwmchip8`/`pwmchip7` and GPIO 54/55/56, see [lp_app.md](../sbin/lp_app.md).)
