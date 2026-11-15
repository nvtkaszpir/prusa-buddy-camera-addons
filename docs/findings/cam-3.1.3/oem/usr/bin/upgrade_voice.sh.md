# `upgrade_voice.sh`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/upgrade_voice.sh` |
| file type | `POSIX shell script, ASCII text executable` |
| size | `1059` |
| sha256 | `f2c7c9a6b306dd1fb56ea44376146812c04fe8b6c4afb5aa4a3fbee5c9598bab` |
| linked libraries | `n/a` |
| origin | Vendor-specific (camera OEM) helper script |
| confidence | high |

## Summary

Plays the one-shot "upgrade successful" voice prompt after a firmware update, at the volume the user configured, and then deletes the wav so the prompt plays only once.

## Usage

It takes no arguments and is run as `upgrade_voice.sh &` from `RkLunch.sh` `post_chk()`. Its configuration comes from `/userdata/xhr_config.ini`, from the line `volume=<n>`.

## How it works

1. Defaults: `VOLUME=40`, valid range 5–100.
2. If `/userdata/xhr_config.ini` exists, it extracts the value of the `^volume=` line (`grep | cut -d= -f2 | tr -d '[:space:]'`).
   - If the value is empty or not numeric, it prints `Volume not valid (...)` and keeps 40.
   - If it is numeric and between 5 and 100, it uses that value.
   - Otherwise it prints `Volume out of range (...)` and keeps 40.
3. If the config file does not exist, it prints `File doesn't exist: ..., set default value 40`.
4. It prints `Used volume: $VOLUME`.
5. If `/oem/usr/etc/upgrade_successful.wav` exists, it prints `Play audio`, runs `simple_ao -i /oem/usr/etc/upgrade_successful.wav -v $VOLUME`, then runs `rm` on the wav.

## Interfaces touched

- Device nodes / sysfs / procfs: audio output, indirectly through `simple_ao` (Rockchip rockit AO sample).
- Files and paths read/written: reads `/userdata/xhr_config.ini`; reads and deletes `/oem/usr/etc/upgrade_successful.wav`.
- Network: none.
- Environment variables / config files: `/userdata/xhr_config.ini` (`volume=`).

## Relevance on this camera

It runs at every boot from `RkLunch.sh`, but it only does something when `/oem/usr/etc/upgrade_successful.wav` exists. In this dump that file is absent, so the OTA/recovery process presumably drops it after an update [INFERENCE]. Because `/` is remounted read-only and the wav lives on `/oem`, the `rm` works only if `/oem` is a separate writable mount [INFERENCE]. The script runs in parallel with the `lp_app` start, so `simple_ao` and lp_app may contend for the audio device [INFERENCE].

## Evidence

```
$ cat oem/usr/bin/upgrade_voice.sh   (quoted above)
CONFIG_FILE="/userdata/xhr_config.ini"
DEFAULT_VOLUME=40 MIN_VOLUME=5 MAX_VOLUME=100
simple_ao -i /oem/usr/etc/upgrade_successful.wav -v $VOLUME
$ ls oem/usr/etc/*.wav  -> upgrading.wav etc. present; upgrade_successful.wav absent
$ grep -rl upgrade_voice .  -> oem/usr/bin/RkLunch.sh
```

## Open questions

- I did not determine which component creates `upgrade_successful.wav`.
- I did not determine which other keys `xhr_config.ini` contains; it is lp_app's config [INFERENCE].
