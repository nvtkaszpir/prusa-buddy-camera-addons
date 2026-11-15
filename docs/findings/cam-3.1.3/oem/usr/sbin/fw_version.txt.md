# `fw_version.txt`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/fw_version.txt` (dump only; **absent on the live camera**) |
| file type | `ASCII text` |
| size | `6` |
| sha256 | `b2f44d3b6e29f8b1b73ea4735f006affc4d198e1fd9c7d50e736159b1ef636c6` |
| linked libraries | `n/a` |
| origin | Vendor build or packaging artifact recording the application firmware version [INFERENCE] |
| confidence | high (contents, no readers); medium (purpose) |

## Summary

A one-line text file containing `3.1.0`. This matches the version string compiled into the `lp_app` build in the same dump. Nothing in the dump reads it: the camera application uses its own built-in version constant. The file seems to be a leftover marker from building or packaging the firmware image, and the newer firmware on the live camera no longer ships it.

## Usage

Not an executable; no arguments or environment. Contents, verbatim (`xxd`: `332e 312e 300a`):

```
3.1.0
```

## How it works

It is a plain data file with one line, `3.1.0` followed by a newline.

Where the version actually comes from:

- The dump `lp_app` contains the literal `3.1.0` at file offset `0x24571c` (vaddr `0x25571c`). The only reference to it is a literal-pool entry at `0x1e7d4`, inside static-initialiser code that registers destructors with `__aeabi_atexit`. In other words, `3.1.0` initialises a global `std::string` when the program starts.
- [INFERENCE] That global is what `lp_app` reports as its firmware version: in `Current version: %s %s`, in the HTTP header `X-Camera-FW-Version`, and in the OTA `last_version` comparison.
- The live `lp_app` (4765884 bytes) instead contains the literal `3.1.3` and still includes `Current version: %s %s` and `X-Camera-FW-Version`. This is consistent with the version being compiled in rather than read from this file.

No file in the dump contains the strings `fw_version.txt` or `version.txt`. The one other match for the pattern `fw_ver` is the Realtek driver `oem/usr/ko/8188fu.ko`, an unrelated driver-internal identifier.

## Interfaces touched

- Device nodes / sysfs / procfs: none found.
- Files and paths read/written: none (passive file). No reader found in the dump.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

- Not referenced by any boot script ([`RkLunch.sh`](../bin/RkLunch.sh.md), `/etc/init.d/*`, `/oem/usr/etc/init.d/S10ntp`), by `lp_app` (dump or live build), by `wifi_setup.sh`/`eth_monitor.sh`, or by any library in `/oem/usr/lib` or `/lib`.
- **Absent on the live camera:** its `/oem/usr/sbin` contains the same scripts and tools but no `fw_version.txt`, together with a newer `lp_app` that embeds `3.1.3`. Its absence has no functional effect.
- Useful for documentation: it confirms that the dumped `/oem` image is application version **3.1.0**, which matches the embedded `lp_app` constant.

## Evidence

```
$ cat oem/usr/sbin/fw_version.txt ; xxd oem/usr/sbin/fw_version.txt
3.1.0
00000000: 332e 312e 300a                           3.1.0.
$ stat -c '%s %y' oem/usr/sbin/fw_version.txt
6 2025-06-27 21:09:22.000000000 +0200
$ grep -rlaE 'wifi_setup|eth_monitor|fw_version' downlaods/3/dump/
./oem/usr/bin/RkLunch.sh ./oem/usr/sbin/lp_app ./oem/usr/sbin/wifi_setup.sh   (none contain fw_version)
$ grep -rlaE 'fw_version|FW_VERSION|fw_ver' downlaods/3/dump/ downlaods/live-3.1.3/oem/usr/sbin/lp_app
./oem/usr/ko/8188fu.ko
$ grep -rlaE 'version\.txt' downlaods/3/dump/ downlaods/live-3.1.3/oem/usr/sbin/lp_app
(no output)
$ strings -n 3 -t x oem/usr/sbin/lp_app | grep -E '3\.1\.0|Current version|X-Camera-FW-Version'
 24571c 3.1.0
 245998 Current version: %s %s
 245cba X-Camera-FW-Version
# xref: 0x25571c referenced only from literal pool 0x1e7d4 (static-init code, __aeabi_atexit at 0x1e798)
$ strings -n 5 -t x downlaods/live-3.1.3/oem/usr/sbin/lp_app | grep -E '^ *[0-9a-f]+ [0-9]+\.[0-9]+\.[0-9]+$'   # live 3.1.3 build, md5 ee845fa0b2e4a8cc0eaf5d7135b8f144
 3b1c8c 3.1.3
```

## Open questions

- Whether any off-device tool (factory flashing or the OTA packaging pipeline) uses this file cannot be determined from the dump [INFERENCE: likely a packaging leftover].
- The connection between the embedded `3.1.0` constant and the `X-Camera-FW-Version` / `Current version` uses was not traced through the disassembly [INFERENCE].
