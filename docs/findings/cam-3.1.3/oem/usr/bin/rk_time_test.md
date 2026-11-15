# `rk_time_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_time_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `30156` |
| sha256 | `c7ddbd8bbf343300736ad47d10dbf4a5e46bedbaa19d95854a1d92b167c63718` |
| linked libraries | `libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK "sysutils" test program; the `librksysutils` code is compiled into the binary (byte-identical to `/oem/usr/lib/librksysutils.so`) |
| confidence | high |

## Summary

A one-shot test program for the RTC. It runs these steps in order:

1. Reads the RTC time and prints it.
2. Sets both the RTC and the system clock to the fixed date **2020-02-18 09:00:00**.
3. Programs an RTC alarm for 09:02:00, reads the alarm back and prints it.
4. Enables the alarm interrupt and waits up to 500 s for it to fire (`alarm rang` / `alarm timeout`).

## Usage

None found. There are no options or help text, and `main` ignores `argc`/`argv`. Output strings:

```
current time : %04d-%02d-%02d %02d:%02d:%02d
SET TIME=%04d-%02d-%02d,%02d:%02d:%02d
alarm time : %02d:%02d:%02d
alarm rang | alarm timeout | EINTR occur
rk_system_get_time fail! / rk_system_set_time fail! / rk_system_set_alarm fail /
rk_system_get_alarm fail / rk_system_enable_alarm fail / rk_system_wait_alarm fail
```

## How it works

The binary imports only libc. The library is linked in statically at an offset of 0xF884. Main is at 0x10f54. It allocates two 44-byte `struct tm` buffers.

1. `rk_system_get_time(&out)` (lib 0x51b8): `open("/dev/rtc", O_RDONLY)` and `ioctl(RTC_RD_TIME 0x80247009)`. Main prints `current time :` with year+1900 and month+1.
2. `rk_system_set_time(&in)` with year 2020, mon 2, mday 18, 09:00:00 (lib 0x52e8):
   - The library takes a human year and a 1-based month (it subtracts 1900 and 1).
   - It range-checks each field (`Year input wrong` … `Second input wrong`).
   - `open("/dev/rtc", O_RDWR)`, `ioctl(RTC_SET_TIME 0x4024700a)`.
   - It then calls `mktime` and `settimeofday()`, so the system clock is set too (`permission denied` / `Parameter setting error` on EPERM/EINVAL).
   - Main prints `SET TIME=2020-02-18,09:00:00`.
3. `rk_system_set_alarm(&in)` with 09:02:00 (lib 0x5738): validates hour, minute and second, then `open("/dev/rtc", O_WRONLY)` and `ioctl(RTC_ALM_SET 0x40247007)`.
4. `rk_system_get_alarm(&out)` (lib 0x5634): `ioctl(RTC_ALM_READ 0x80247008)`. Main prints `alarm time : %02d:%02d:%02d`.
5. `rk_system_enable_alarm()` (lib 0x58f0): `ioctl(RTC_AIE_ON 0x7001)`.
6. `rk_system_wait_alarm(500)` (lib 0x5a48): `open("/dev/rtc")`, then `select()` on the fd with `tv_sec = 500`.
   - If the fd becomes readable: `alarm rang`.
   - On timeout: `alarm timeout` (errno set to ETIMEDOUT).
   - On EINTR: `EINTR occur`.
7. It frees both buffers and returns 0. It does **not** call `rk_system_disable_alarm` (RTC_AIE_OFF), so the alarm interrupt stays enabled.

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/rtc` (ioctls RTC_RD_TIME, RTC_SET_TIME, RTC_ALM_SET, RTC_ALM_READ, RTC_AIE_ON; `select` for the alarm). The dump shows `/dev/rtc -> rtc0` (char 251:0).
- Files and paths read/written: none besides the above. The system clock is set via `settimeofday`.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not started at boot. There are no references to `rk_time_test` in `downlaods/3/dump/` (init scripts, `RkLunch.sh`, `oem/usr/etc/init.d`).
- **Side effects:**
  - Both the hardware RTC and the Linux system clock jump to 2020-02-18 09:00:00.
  - On a networked camera this can break TLS certificate validation and cloud/Prusa Connect communication, timestamps in lp_app logs, and time-based features until NTP or the app resyncs. [INFERENCE]
  - It leaves the RTC alarm armed (09:02:00) with AIE enabled.
  - It runs for up to ~500 s (about 2 min if the alarm fires, given the clock was just set to 09:00:00).
- No camera, encoder or audio conflict with lp_app, apart from the clock change.

## Evidence

```
$ readelf -d rk_time_test | grep NEEDED  -> [libc.so.0]
$ strings -t x rk_time_test
   593c Malloc input struct tm fail!
   5998 current time : %04d-%02d-%02d %02d:%02d:%02d
   59e4 SET TIME=%04d-%02d-%02d,%02d:%02d:%02d
   5a44 alarm time : %02d:%02d:%02d
   ... /dev/rtc, error RTC_SET_TIME ioctl, alarm rang, alarm timeout (library)
$ readlink dump/dev/rtc -> rtc0
```
Main excerpt:
```
11004: bl 0x14a3c                    ; rk_system_get_time
11088: movw r2,#2020 ; str [tm,#20]   ; year
11094: mov r2,#2 (mon) ; #18 (mday) ; #9 (hour) ; #0 ; #0
110d0: bl 0x14b6c                    ; rk_system_set_time
1116c: mov #9 (hour) ; #2 (min) ; #0 (sec)
11190: bl 0x14fbc                    ; rk_system_set_alarm
111c0: bl 0x14eb8                    ; rk_system_get_alarm
11210: bl 0x15174                    ; rk_system_enable_alarm
1123c: mov r0,#500 ; bl 0x152cc      ; rk_system_wait_alarm(500)
```
Library: `5540: ioctl 0x4024700a (RTC_SET_TIME)`, `5524: bl mktime`, `558c: bl settimeofday`, `5880: 0x40247007 (RTC_ALM_SET)`, `593c: 0x7001 (RTC_AIE_ON)`, `5b2c: tv_sec = timeout ; bl select`.

## Open questions

- Whether the board's RTC (the rtc0 driver) supports alarms. If not, `RTC_ALM_SET` or `RTC_AIE_ON` fails and the program exits early.
- How lp_app and the system resync time afterwards (NTP client not examined here).
