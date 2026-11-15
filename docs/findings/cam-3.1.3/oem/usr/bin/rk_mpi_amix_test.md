# `rk_mpi_amix_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_amix_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `13792` |
| sha256 | `72aad958a0e4d7d98e6da082dd867e8d37383867c5f1d8830dbcc852ca619615` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rockit/rkmpi unit test `rk_mpi_amix_test` [INFERENCE: SDK naming/argparse skeleton] |
| confidence | high |

## Summary

AMIX is rockit's audio mixer API (`RK_MPI_AMIX_*`), a thin wrapper over the ALSA control interface of a sound card. It does the same job as `amixer`/`tinymix`: list the mixer controls, show their contents, and get or set one control by name. This program is that `amixer`-like command-line tool. On this camera it can read and change the internal audio codec's (acodec) mixer settings, such as gains, switches and routes.

## Usage

The option table was rebuilt from the argparse table built in `main` (ctx = `malloc(20)` zeroed). The ctx fields are: +0 card, +4 control, +8 value, +12 list_controls, +16 list_contents.

```
./rk_mpi_amix_test [-C card] [--control ctl_name] [--value ctl_val] [--list_controls] [--list_contents]...

select a test case to run.
use --help for details.
```

| short | long | type | help text (verbatim) | default in code |
|---|---|---|---|---|
| `-h` | `--help` | flag | show this help message and exit | – |
| `-C` | `--card` | int | specifies the card number of the mixer. default(0) | 0 |
| | `--control` | str | sets (or gets without control value) the name of a control. default(required) | NULL |
| | `--value` | str | sets the value of a control. default(required) | NULL |
| | `--list_controls` | bool | lists controls of the mixer. default(false). | 0 |
| | `--list_contents` | bool | lists controls of the mixer and their contents. default(false). | 0 |

Typical use: `rk_mpi_amix_test --list_contents` (card 0), `rk_mpi_amix_test --control '<name>'` (get), `rk_mpi_amix_test --control '<name>' --value '<val>'` (set). The control names come from the acodec driver and are not in this binary.

## How it works

`main` (0x10cc4) parses the options and prints "cmd parse result:" ("sound control id", "control name", "control value", "list controls", "list contents"). Then:

- If `--control` is given with `--value`, it calls `RK_MPI_AMIX_SetControl(card, control, value)`.
- If `--control` is given without `--value`, it calls `RK_MPI_AMIX_GetControl(card, control, buf)` and prints "Get current control value: %s". It then prints "List the control values:" and calls `RK_MPI_AMIX_GetControl(card, control, NULL)`, which presumably makes librockit list all enumerated values [INFERENCE].
- If `--list_controls` is set, it calls `RK_MPI_AMIX_ListControls(card)`.
- If `--list_contents` is set, it calls `RK_MPI_AMIX_ListContents(card)`.
- If no control is given and neither list flag is set, it calls `argparse_usage` and returns -1.

It does not call `RK_MPI_SYS_Init`. The AMIX calls work directly on ALSA.

## Interfaces touched

- Device nodes / sysfs / procfs: the ALSA control device `/dev/snd/controlC<card>`. librockit.so contains the format string `/dev/snd/controlC%u`. On this camera card 0 is `platform-acodec-sound` (`dump/dev/snd/by-path/platform-acodec-sound -> ../controlC0`; udev data `c116:0`).
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not started at boot and not referenced anywhere. A grep of `downlaods/3/dump/` for `rk_mpi_amix_test` matches only the binary itself. No init script or `lp_app.sh` uses it.

Of this batch it is the most practically useful tool for inspecting the camera's audio codec: `--list_contents` is read-only and safe. `--value` writes take effect immediately on the live codec and also affect `lp_app`'s audio, for example muting the microphone or changing the ADC gain [INFERENCE]. They last until something resets them; ALSA mixer state is not saved to flash by this tool, and there is no `alsactl store` in the flow.

## Evidence

- `llvm-nm-14 -D` imports: `RK_MPI_AMIX_SetControl`, `RK_MPI_AMIX_GetControl`, `RK_MPI_AMIX_ListControls`, `RK_MPI_AMIX_ListContents` (no `RK_MPI_SYS_*`).
- `strings`: `Get current control value: %s`, `List the control values:`, `sound control id      : %d`.
- Disassembly of `main` (decision logic):
  ```
  10ea4 ldr r1,[r4,#4] ; cmp r1,#0 ; beq <no control>
  10eb0 ldr r5,[r4,#8] ; cmp r5,#0 ; beq <get>
  10ec4 bl RK_MPI_AMIX_SetControl
  10f18 bl RK_MPI_AMIX_GetControl ; printf "Get current control value: %s" ; 10f40 bl RK_MPI_AMIX_GetControl
  10f70 bl RK_MPI_AMIX_ListContents ; 10f7c bl RK_MPI_AMIX_ListControls
  10f88 bl argparse_usage ; mvn r0,#0
  ```
- librockit.so exports `RK_MPI_AMIX_{GetControl,ListContents,ListControls,SetControl}` and contains `/dev/snd/controlC%u`.

## Open questions

- The list of acodec mixer control names on this firmware needs either the kernel driver or a run of `--list_contents` on the device; it is not available statically.
- The exact semantics of the second `GetControl` call (NULL buffer) depend on librockit internals [INFERENCE].
