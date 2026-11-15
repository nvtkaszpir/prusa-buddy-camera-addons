# logrotate

Rotates the add-on logs (dropbear, lighttpd, rsyslog) once a day and keeps the last 7 dated copies,
uncompressed. It uses a static logrotate 3.22.0 binary that is driven by an hourly shell loop, because
the camera has no cron.

## How it works

- `/mnt/sdcard/lp_app.sh` runs `sh /mnt/sdcard/bin/start-logrotate.sh` at boot. The hook block comes
  from `buddy-addons/device/logrotate-hook.sh`. Paste it after the syslog block and before
  `/tmp/sync_loop.sh`.
- `start-logrotate.sh` copies these files when their md5 differs (the card copy wins):
  - `/mnt/sdcard/bin/logrotate` -> `/userdata/bin/logrotate`
  - `/mnt/sdcard/bin/logrotate.conf` -> `/userdata/logrotate/logrotate.conf`
- Schedule: there is no cron. The script copies itself to `/tmp/logrotate-loop.sh` and starts a
  background loop (pid in `/tmp/logrotate-loop.pid`, output in `/tmp/logrotate-loop.out`). The loop
  sleeps 3600 s, then runs `logrotate -s /userdata/logrotate/status /userdata/logrotate/logrotate.conf`.
  It skips the run while the clock still shows a year before 2025, which happens until NTP sets the time.
- The state file `/userdata/logrotate/status` survives reboots and decides when `daily` is due. So
  each file is rotated at most once a day, even though logrotate runs every hour.
- The loop runs from `/tmp`, so it keeps running when `sync_loop.sh` kills lp_app. The card can also
  be unmounted while it runs. The loop is lost on reboot and starts again from the hook.
- Settings in `buddy-addons/device/logrotate.conf`: `daily`, `rotate 7`, `dateext`,
  `dateformat -%Y%m%d`, `nocompress`, `missingok`, `notifempty`, `su root root`, `nocreate`.
- Rotated files:

| file | method |
|---|---|
| `/mnt/sdcard/logs/dropbear.log` | copytruncate |
| `/mnt/sdcard/logs/httpd.log` | copytruncate |
| `/mnt/sdcard/logs/rsyslog.log` | copytruncate |
| `/tmp/dropbear.log` | copytruncate |
| `/tmp/lighttpd.log` | rename, then `SIGHUP` to the pid in `/tmp/lighttpd.pid` |

- Rotated copies are named `<name>.log-YYYYMMDD`. That name does not match `*.log`, so rsyslog's
  imfile does not forward them again. See [rsyslog](rsyslog.md): its config needs
  `reopenOnTruncate="on"` because of copytruncate.
- Not rotated: lp_app's own hourly logs `/mnt/sdcard/logs/YYYY-MM-DD_HH.log` (about 583 MB at the last
  check). The config contains a commented-out `find ... -mtime +7` prune command that nothing runs.
- `/tmp` logs and their rotated copies are lost on reboot.
- Script steps and logrotate errors go to `/mnt/sdcard/logs/logrotate.log`. If the logs directory
  does not exist, they go to `/tmp/logrotate.log`.

## What to change

Nothing is required. The defaults work as shipped. Optional changes:

- Retention: `buddy-addons/device/logrotate.conf`, `rotate 7`. Raise or lower it to keep more or
  fewer daily copies.
- Compression: `buddy-addons/device/logrotate.conf`, `nocompress`. Change it to `compress` to save
  card space. `[INFERENCE]` The static build has to find a `gzip` binary on the camera at run time.
  The sources do not check whether one exists.
- Frequency: `daily` in `buddy-addons/device/logrotate.conf` (for example `weekly`, or `size`
  rules). The loop interval is `sleep 3600` in `loop()` in `buddy-addons/device/start-logrotate.sh`.
  Keep the loop at least as frequent as the rotation period.
- Rotated copy names: `dateext` / `dateformat -%Y%m%d` in the config. Keep the suffix from ending in
  `.log`, or rsyslog will forward the copies again.
- Log paths: the file list blocks in the config. Add a file to the `copytruncate` block if its writer
  appends with `O_APPEND`. Use a `postrotate` signal if the writer reopens its file on a signal, as
  lighttpd does.
- Clock guard: `[ "$(date +%Y)" -ge 2025 ]` in `start-logrotate.sh`. It only needs a change if the
  camera clock is expected to be earlier than that.
- Install paths: `SRC`, `BIN`, `DIR`, `CONF`, `STATE` at the top of `start-logrotate.sh`. Defaults are
  `/mnt/sdcard/bin`, `/userdata/bin`, `/userdata/logrotate`, `$DIR/logrotate.conf`, `$DIR/status`.

!!! warning
    Keep `su root root` and `nocreate`. logrotate refuses files in directories that others can write
    to. The vfat card (777) and `/tmp` (1777) are both like that. vfat also ignores the chown that
    `create` does.

## Build and deploy

```sh
cd buddy-addons && ./build-logrotate.sh   # -> buddy-addons/out/logrotate
cd .. && task buddy:sync                  # stage + rsync to root@CAMERA_HOST:/mnt/sdcard/bin/
```

`task buddy:stage` copies `buddy-addons/device/*` and `out/logrotate` into
`buddy-addons/build/device-stage`. `task buddy:sync` needs a working [SSH](ssh.md) and [rsync](rsync.md)
setup on the camera. Set `CAMERA_HOST` in `Taskfile.yml` (default `192.168.1.75`). Hook files are
excluded from the sync, so paste the `buddy-addons/device/logrotate-hook.sh` block into
`/mnt/sdcard/lp_app.sh` once by hand.

## Verify

```sh
/userdata/bin/logrotate --version                     # logrotate 3.22.0
cat /tmp/logrotate-loop.pid && ps | grep logrotate-loop
cat /mnt/sdcard/logs/logrotate.log
sh /mnt/sdcard/bin/start-logrotate.sh run             # rotate now, if due
/userdata/bin/logrotate -f -s /userdata/logrotate/status /userdata/logrotate/logrotate.conf  # force
ls /mnt/sdcard/logs/*.log-* /tmp/*.log-*
sh /mnt/sdcard/bin/start-logrotate.sh stop            # stop the loop
```

A file with no state entry is first rotated the day after its first check. A second forced run on the
same day skips every file (`destination ... already exists`).

## Source files

- `buddy-addons/logrotate.md`
- `buddy-addons/build-logrotate.sh`
- `buddy-addons/device/logrotate.conf`
- `buddy-addons/device/logrotate-hook.sh`
- `buddy-addons/device/start-logrotate.sh`
- `Taskfile.yml`
