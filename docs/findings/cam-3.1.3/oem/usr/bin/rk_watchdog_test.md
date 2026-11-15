# `rk_watchdog_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_watchdog_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30176` |
| sha256 | `bc29f835eb04dc0e63b72057ce3c8e34ea5564bd4525380add84a65cff1411c6` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary rather than linked (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A test program for the hardware watchdog. It opens `/dev/watchdog`, enables it with the driver's default timeout, and starts a thread that sends a keepalive every second. The main thread reads stdin until you type `quit`, then stops the thread and disarms the watchdog (writes the magic `V`, then `WDIOS_DISABLECARD`). It is a leftover from the SDK. Nothing on the camera starts it.

## Usage

There are no command-line options: `main` ignores `argc`/`argv`. The only interface is stdin:

```
#Usage: input 'quit' to exit programe!
```

- Any stdin line that contains `quit` → prints `#Get 'quit' cmd!`, stops the feeder thread, disarms the watchdog and exits.
- Any other line → prints `alive` and sleeps 0.5 s.
- The feeder thread prints `.<n>` once per second (n counts 0..59 and wraps).

## How it works

The binary imports only libc. The watchdog code is a static copy of `librksysutils.so`: the same strings, and function bytes that match the library at a constant offset of 0xF8A0. Main is at 0x110B8 (taken from the `__uClibc_main` argument in `_start`).

1. `setbuf(stdout, NULL)`.
2. `rk_watchdog_start(0)` (lib 0x5d70):
   - `open("/dev/watchdog", O_WRONLY)`. On failure it prints `Watchdog device not enabled.` (ENOENT), `Run watchdog as root.` (EACCES) or `Watchdog device open failed %s`.
   - `ioctl(fd, WDIOC_SETOPTIONS (0x80045704), &WDIOS_ENABLECARD (2))` → `Watchdog card enabled.`
   - It calls `WDIOC_SETTIMEOUT (0xC0045706)` only when the timeout argument is > 0. This program passes 0, so the kernel or driver default timeout stays in effect.
   - If enabling fails, it writes `V` (the magic-close character, `v` symbol at lib .rodata 0x6b14), closes the fd and returns -1.
   - If start fails, main prints `rk_watchdog_start fail!` and carries on anyway.
3. `pthread_create(feeddog_thread)` (0x1102c). The loop runs `rk_watchdog_refresh()`, which is `ioctl(fd, WDIOC_KEEPALIVE (0x80045705))` and prints `rk_watchdog_refresh fail` on error. It then prints `.%d` and calls `sleep(1)`, repeating until a global stop flag is set.
4. Main loop: `fgets(stdin, 64)`, then `strstr(buf, "quit")`. If not found, `puts("alive")` and `usleep(500000)`.
5. On `quit`: set the stop flag, `pthread_cancel`, `pthread_join` (error: `rk_feeddog_thread join failed!`), then `rk_watchdog_stop()` (lib 0x5c24). That does `write(fd, "V", 1)`, then `ioctl(WDIOC_SETOPTIONS, WDIOS_DISABLECARD (1))` → `Watchdog card disabled.`, then `close(fd)`.

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/watchdog` (`open` O_WRONLY; ioctls WDIOC_SETOPTIONS, WDIOC_KEEPALIVE; optional WDIOC_SETTIMEOUT, which this program never issues; magic-close write `V`).
- Files and paths read/written: none other than the above; stdin/stdout.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. A grep of the whole `downlaods/3/dump/` tree for `rk_watchdog_test` finds no references in `etc/init.d/S*`, `RkLunch.sh` or `oem/usr/etc/init.d/S*`. The only file mentioning `/dev/watchdog` is this binary family plus `librksysutils.so`. `lp_app` (`/oem/usr/sbin/lp_app`) contains no `/dev/watchdog` or `rk_watchdog_*` strings, and its DT_NEEDED list does not include `librksysutils.so`.
- `/dev/watchdog` may not exist on this unit. The dumped `/dev/char/` symlinks contain no misc 10:130 (watchdog) entry. If so, the program prints `Watchdog device not enabled.` and `rk_watchdog_start fail!`, then `rk_watchdog_refresh fail` every second (it keeps running and ioctls an invalid fd). [INFERENCE]
- **Side effect / reboot risk:** if a watchdog device does exist, the program arms it. Leaving without typing `quit` skips the magic `V` and `WDIOS_DISABLECARD`; that includes Ctrl-C, SIGKILL, closing the telnet session, or stdin hitting EOF while the process is blocked. In those cases the watchdog stays armed with no one feeding it, and the camera reboots when the default timeout expires. With `CONFIG_WATCHDOG_NOWAYOUT`, or a driver without a stop operation (Rockchip `dw_wdt` cannot truly stop), even a clean `quit` may not disarm it. [INFERENCE]
- It does not conflict with the camera pipeline (no VI/VENC/audio use).

## Evidence

```
$ readelf -d rk_watchdog_test | grep NEEDED      -> [libc.so.0]
$ llvm-nm-14 -D --undefined-only rk_watchdog_test  -> libc only (ioctl, open, write, pthread_create, pthread_cancel, pthread_join, fgets, strstr, setbuf, sleep, usleep ...)
$ strings -t x rk_watchdog_test
   595c rk_watchdog_start fail!
   5974 rk_feeddog_thread create failed!
   5999 #Usage: input 'quit' to exit programe!
   59c0 quit / 59c8 #Get 'quit' cmd! / 59dc alive
   59e4 rk_feeddog_thread join failed!
   64c4 /dev/watchdog
   652c Watchdog card enabled. / 648c Watchdog card disabled.
   6564 Watchdog timeout set to %u seconds.
```
Library-copy offset: the first 12 bytes of `rk_adc_get_devnum`, `rk_gpio_export` and `rk_system_get_time` from `librksysutils.so` are found at lib_addr+0xF8A0.

Main (annotated `llvm-objdump` excerpt):
```
110f0: bl setbuf
110f4: mov r0,#0 ; bl 0x15610   ; rk_watchdog_start(0)
11144: bl pthread_create          ; thread fn 0x1102c
11194: bl fgets ; bl strstr("quit")
111e0: movw/movt r0,#0x7a120 ; bl usleep   ; 500 ms
1122c: bl pthread_cancel ; 11244: bl pthread_join
11284: bl 0x154c4               ; rk_watchdog_stop
thread 0x1102c: bl 0x158dc (rk_watchdog_refresh) ; printf(".%d") ; sleep(1)
```
Library (`librksysutils.so`):
```
5db4: open("/dev/watchdog", 1)
5e78: movw r1,#22276 ; movt r1,#32772  -> 0x80045704 WDIOC_SETOPTIONS, arg 2 (ENABLECARD)
5f2c: 0xC0045706 WDIOC_SETTIMEOUT (only if timeout>0)
6058: 0x80045705 WDIOC_KEEPALIVE
5c68: write(fd, v="V", 1) ; 5cb4: WDIOC_SETOPTIONS arg 1 (DISABLECARD)
```

## Open questions

- Whether the running kernel exposes `/dev/watchdog` at all. The dump has no 10:130 node symlink. [INFERENCE]
- The default watchdog timeout and the `nowayout` setting, i.e. whether `quit` really disarms it. These can't be determined from userland.
- Whether the bootloader or kernel already starts the hardware watchdog independently of this tool. Unknown.
