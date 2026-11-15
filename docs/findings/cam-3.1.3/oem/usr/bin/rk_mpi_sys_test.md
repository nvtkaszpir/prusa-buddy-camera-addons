# `rk_mpi_sys_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rk_mpi_sys_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `17920` |
| sha256 | `36b32734ec96fd7dcce650af67e8254fcc7dc90f624d98949af19776b496851a` |
| linked libraries | `librockit.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip RV1106 SDK rockit/rkmpi unit test (`rk_mpi_sys_test`, `mpi/example`) |
| confidence | high |

## Summary

Rockchip rkmpi unit test for the SYS module's bind bookkeeping. It sets up an audio-decoder (ADEC) channel and an audio-output (AO) device on ALSA `hw:0,0`. It binds ADEC→AO with `RK_MPI_SYS_Bind` and verifies the binding with `RK_MPI_SYS_GetBindbySrc`/`GetBindbyDest`. It then unbinds and tears everything down, repeating `loop_count` times. No audio data is decoded or played. It is an SDK developer test.

## Usage

Usage string (verbatim): `./rk_mpi_sys_test...`. Descriptions: `"\nselect a test case to run."`, `"\nuse --help for details."`.

Reconstructed argparse option table (help verbatim):

| short | long | type | help |
|---|---|---|---|
| — | `--help` | bool | show this help message and exit |
| | | group | basic options: |
| `-n` | `--loop_count` | int | loop running count. default(1) |
| — | `--device_id` | int | MODULE device id. default(0) |
| — | `--src_channel_id` | int | source MODULE channel id. default(0) |
| — | `--dst_channel_count` | int | the count of dst MODULE channel. default(1) |

Here `device_id` is the AO device, `src_channel_id` is the ADEC channel, and `dst_channel_count` is the number of AO channels bound [INFERENCE from usage in `unit_test_mpi_sys_bind`].

## How it works

1. argparse → `RK_MPI_SYS_Init` → `unit_test_mpi_sys(ctx)` → `RK_MPI_SYS_Exit`. Logs `test running ok.` / `test running failed!`.
2. `unit_test_mpi_sys` calls `unit_test_mpi_sys_bind` `loop_count` times (`looping times %d`).
3. `unit_test_mpi_sys_bind`:
   - `test_ao_dev_init`: fills `AIO_ATTR_S` with card name `"hw:0,0"` → `RK_MPI_AO_SetPubAttr` → `RK_MPI_AO_Enable`.
   - `test_adec_create_channel`: `malloc` of an `ADEC_CHN_ATTR_S` (constants include channels 1 and sample rate 8000) → `RK_MPI_ADEC_CreateChn` (`failed to create adec chn %d, err %d`).
   - For each destination channel: `RK_MPI_AO_EnableChn` → `RK_MPI_SYS_Bind(ADEC src → AO dst)` → `succeed to bind ADEC(%d) AO(%d)`.
   - `test_mpi_sys_get_bind_by_src` (`RK_MPI_SYS_GetBindbySrc`, prints `get dst channel(modId=%d, devId=%d, chnId=%d)`) and `test_mpi_sys_get_bind_by_dest` (`RK_MPI_SYS_GetBindbyDest`, prints `get src channel(...)`).
   - `RK_MPI_SYS_UnBind` → `succeed to unbind ADEC(%d) AO(%d)` → `RK_MPI_AO_DisableChn` → `RK_MPI_ADEC_DestroyChn` → `test_ao_dev_deinit` (`RK_MPI_AO_Disable`).

## Interfaces touched

- Device nodes / sysfs / procfs: ALSA card `hw:0,0` via the AO module, i.e. `/dev/snd/pcmC0D0p` / `/dev/snd/controlC0` (librockit.so contains `/dev/snd/pcmC%uD%u%c`, `/dev/snd/controlC%u`) [INFERENCE]. Also `/dev/mpi/vsys` via librockit [INFERENCE].
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none found.

## Relevance on this camera

Nothing starts it at boot. There are no references in `downlaods/3/dump/` (init scripts, `RkLunch.sh`) other than the binary itself, and `lp_app` does not depend on it. When run, it briefly opens the ALSA playback device `hw:0,0`. If `lp_app` or another process holds that device, `RK_MPI_AO_Enable` fails. Otherwise it opens and closes it without playing audio, possibly producing a click if a speaker or amplifier is attached [INFERENCE]. It writes no files and has no flash, GPIO or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D --undefined-only rk_mpi_sys_test | grep RK_
 RK_LOG RK_MPI_ADEC_CreateChn RK_MPI_ADEC_DestroyChn RK_MPI_AO_Disable RK_MPI_AO_DisableChn RK_MPI_AO_Enable
 RK_MPI_AO_EnableChn RK_MPI_AO_SetPubAttr RK_MPI_SYS_Bind RK_MPI_SYS_Exit RK_MPI_SYS_GetBindbyDest
 RK_MPI_SYS_GetBindbySrc RK_MPI_SYS_Init RK_MPI_SYS_UnBind
internal: test_ao_dev_init, test_ao_dev_deinit, test_adec_create_chn_attr, test_adec_create_channel,
 test_ao_enable_channel, test_bind_adec_ao, test_unbind_adec_ao, test_mpi_sys_get_bind_by_src/dest,
 unit_test_mpi_sys_bind, unit_test_mpi_sys
$ strings -t x rk_mpi_sys_test
 2c10 hw:0,0
 2ce0 get dst channel(modId=%d, devId=%d, chnId=%d)
 2d88 succeed to bind ADEC(%d) AO(%d)
 2f4c ./rk_mpi_sys_test...
unit_test_mpi_sys_bind (0x11bc0): "hw:0,0" ; RK_MPI_AO_SetPubAttr ; RK_MPI_AO_Enable ; malloc ; (8000 Hz, 1ch const)
 RK_MPI_ADEC_CreateChn ; RK_MPI_AO_EnableChn ; RK_MPI_SYS_Bind ; GetBindbySrc ; GetBindbyDest ;
 RK_MPI_AO_DisableChn ; RK_MPI_SYS_UnBind ; RK_MPI_ADEC_DestroyChn ; RK_MPI_AO_Disable
```

## Open questions

- Whether the camera has an audio output codec on card 0 was not checked here. If it does not, `RK_MPI_AO_Enable` fails and the test reports failure.
- The ADEC codec type constant (value 4 in the attribute) was not mapped to an `RK_CODEC_ID_E` name.
