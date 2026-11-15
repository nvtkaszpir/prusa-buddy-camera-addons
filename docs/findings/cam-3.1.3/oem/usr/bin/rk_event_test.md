# `rk_event_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_event_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30168` |
| sha256 | `2c9d883bfec224d446f90f360458de83d88a7b2aa6ca4e8094742553f10c1693` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A test program for Linux input events. It registers `/dev/input/event0`, `event1` and `event2` with the `rk_event_*` epoll listener and starts it. Every `struct input_event` it receives is printed (seconds, microseconds, type, code, value). It exits when `quit` is typed on stdin. On this camera `event0` is the ADC-based button input (`platform-adc-keys`).

## Usage

There are no command-line options: `main` ignores `argc`/`argv`. The only interface is stdin:

```
#Usage: input 'quit' to exit programe!
```

Each event is printed as:

```
[eventval:sec:%d, usec:%d, type:%d, code:%d, value:%d]
```

Typing a line that contains `quit` prints `#Get 'quit' cmd!` and exits. Any other line sleeps 0.5 s and the program keeps reading.

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF784 from `librksysutils.so`. Main is at 0x11030; the callback is at 0x10fa8.

1. It copies the four path literals `/dev/input/event0`…`event3` into stack buffers.
2. `rk_event_register()` is called for `event0`, `event1` and `event2` (lib 0x2004):
   - On first use it does `pthread_mutex_init`, allocates the manager and calls `epoll_create1(EPOLL_CLOEXEC)`.
   - Per device it checks for duplicates (`dev_path has been registered!`), then `open(path, O_RDONLY|O_NONBLOCK)` (flags 0x800; `failed open %s` on error).
   - It then calls `epoll_ctl(ADD, EPOLLIN|EPOLLET (0x80000001))`.
3. `rk_event_unregister("/dev/input/event3")`. event3 was never registered, so this only prints `dev_path isn't registered`. It looks like leftover SDK test code.
4. `rk_event_listen_start(cb)` (lib 0x29ec) creates `rk_event_recthread`. That thread calls `epoll_wait`, does `read(fd, buf, 16)` (one 32-bit `struct input_event`) and calls the callback.
5. The callback prints `[eventval:sec:%d, usec:%d, type:%d, code:%d, value:%d]` from the `input_event` fields (tv_sec, tv_usec, type (u16), code (u16), value). It prints `eventcb is null` if it gets a NULL event.
6. Main loop: `fgets(stdin, 64)`, `strstr("quit")`, otherwise `usleep(500000)`.
7. On `quit`: `rk_event_listen_stop()` cancels and joins the thread, closes the fds, frees memory and destroys the mutex.

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/input/event0`, `/dev/input/event1`, `/dev/input/event2` (opened read-only and non-blocking). `/dev/input/event3` is only named in the unregister call.
- Files and paths read/written: none besides stdin/stdout.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_event_test` anywhere in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- The dumped `/dev` has only `input/event0` (char 13:64), and `/dev/input/by-path/platform-adc-keys-event -> ../event0`. Registering `event1` and `event2` would therefore print `failed open /dev/input/event1` / `event2`, and only the adc-keys button events would be printed. [INFERENCE: the runtime device set matches the dump]
- Read-only and non-exclusive (no `EVIOCGRAB` ioctl is used), so it should not take button events away from `lp_app` and has no hardware side effects. `lp_app` contains no `/dev/input/event` string, so how lp_app reads the button is unknown. [INFERENCE]

## Evidence

```
$ readelf -d rk_event_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_event_test
   583c eventcb is null
   584c [eventval:sec:%d, usec:%d, type:%d, code:%d, value:%d]
   5885 #Usage: input 'quit' to exit programe!
   58c8 /dev/input/event0  58dc /dev/input/event1  58f0 /dev/input/event2  5904 /dev/input/event3
$ ls -l dump/dev/input/by-path   -> platform-adc-keys-event -> ../event0
```
Main excerpt:
```
110d4: bl 0x11788 ; rk_event_register(event0)
110e0: bl 0x11788 ; rk_event_register(event1)
110ec: bl 0x11788 ; rk_event_register(event2)
110f8: bl 0x11d18 ; rk_event_unregister(event3)
11108: bl 0x12170 ; rk_event_listen_start(cb)
11138: bl fgets ; 11150: bl strstr("quit") ; 1117c: bl usleep(500000)
1118c: bl 0x122f8 ; rk_event_listen_stop
```
Library: `22d8: mov r1,#2048 ; bl open`, `2148: mov r0,#524288 ; bl epoll_create1`, `2360: mov r2,#0x80000001 ; epoll_ctl`, `28c4: mov r2,#16 ; bl read`.

## Open questions

- Which key codes the adc-keys driver emits (needs the device tree; not in the dump).
- Whether the running kernel exposes more input devices than the dump captured.
