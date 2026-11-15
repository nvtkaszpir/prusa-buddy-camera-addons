# `mpp_info_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/mpp_info_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `9668` |
| sha256 | `e694aaa06f92e6190c04aabc0debd261859fbae995e00520faf3fe00c3e97ff4` |
| linked libraries | `librockchip_mpp.so.1, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip MPP test program `test/mpp_info_test.c` |
| confidence | high |

## Summary

Prints the version information of the installed `librockchip_mpp`: first the normal one-line version, then the embedded git commit history. It is a read-only diagnostic.

## Usage

No usage or help string exists, and `main` never reads `argv`. Run it with no arguments: `mpp_info_test`.

## How it works

`main` (0x10cc0 region) makes these calls in order:

1. `mpp_env_set_u32("mpp_show_history", 0)`
2. `_mpp_log("normal version log:\n")`, then `show_mpp_version()`
3. `mpp_env_set_u32("mpp_show_history", 1)`
4. `_mpp_log("history version log:\n")`, then `show_mpp_version()`
5. `mpp_env_set_u32("mpp_show_history", 0)`

`show_mpp_version` lives in `librockchip_mpp.so.0`. It prints "mpp version: %s" and, when `mpp_show_history` is set, "mpp version history %d:" followed by the embedded commit list. The library on this camera reports HEAD `8cae7ec7 author: toby.zhang 2022-09-29 [Vepu540c]: Adding max frame lvl qp. (HEAD, rk/mpp_interface, m/master, def)`.

The binary also contains the shared MPP test utility code: `event_ctx_create`/`event_ctx_release` and `mpp_parse_config` with strings `[CONFIG]`, `[EVENT]`, `index`, `loop`, `frm`, `msec`. `main` never calls them; they are linked-in dead code.

Output goes to the MPP log, i.e. stdout/stderr via `_mpp_log` [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: none
- Files and paths read/written: none from `main`. (`mpp_parse_config` can `fopen` a config file, but nothing calls it.)
- Network: none
- Environment variables / config files: sets the MPP env value `mpp_show_history` (through `mpp_env_set_u32`).

## Relevance on this camera

- Not started at boot and not referenced by any init script or by `lp_app`.
- Harmless: it opens no device and only prints version strings. Safe to run while `lp_app` is running [INFERENCE: the library may do some init work when it loads, but `main` creates no MPP context].

## Evidence

```
$ readelf -p .rodata mpp_info_test
  [     0]  mpp_show_history
  [    14]  normal version log:\n
  [    3c]  history version log:\n
$ (annotated disassembly of main)
10ce4 str 'mpp_show_history'   10cf0 call mpp_env_set_u32   (r1=#0)
10d00 str 'normal version log:\n'   10d08 call show_mpp_version
10d14 call mpp_env_set_u32 (r1=#1)
10d24 str 'history version log:\n'  10d2c call show_mpp_version
10d38 call mpp_env_set_u32 (r1=#0)
$ strings librockchip_mpp.so.0 | grep -E 'version|author' | head
mpp version history %d:
mpp version: %s
8cae7ec7 author: toby.zhang    2022-09-29 [Vepu540c]: Adding max frame lvl qp.  (HEAD, rk/mpp_interface, m/master, def)
38f81819 author: Zhihua Wang   2022-09-23 [inc]: add motion_static_switch_en
```

## Open questions

- Whether `_mpp_log` goes to stdout, stderr or syslog in this build was not checked statically [INFERENCE: upstream Linux builds print to stdout].
