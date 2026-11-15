# `kill_process.sh`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/kill_process.sh` |
| file type | `POSIX shell script, ASCII text executable` |
| size | `451` |
| sha256 | `6f128d6d6c5f1da819c592211dc5ce817241ab33628a39c00dcd39b7220fe520` |
| linked libraries | `n/a` |
| origin | Vendor/SDK helper script (Chinese comment `使用 kill -9 杀死进程` = "use kill -9 to kill the process") |
| confidence | high |

## Summary

A convenience script that SIGKILLs every process whose `ps` line contains a given string.

## Usage

```
Usage: $0 <process_name>
```

It takes one positional argument, a substring matched against the `ps` output. With no argument it prints the usage line and exits with 1.

## How it works

1. It collects the PIDs with `ps | grep "$PROCESS_NAME" | grep -v grep | awk '{print $1}'`. This is a substring match against the whole `ps` line, so it can also hit unrelated processes whose arguments contain the string.
2. If none are found, it prints `No process found with name: ...` and exits with 1.
3. For each PID it prints `Killing process ... with PID: ...` and runs `kill -9 $PID`.
4. It finishes with `All processes named ... have been killed.`

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc`, indirectly through BusyBox `ps`.
- Files and paths read/written: none.
- Network: none.
- Environment variables / config files: none.

## Relevance on this camera

It is not called at boot. A grep of the whole dump finds no reference to `kill_process.sh` outside the file itself. It is a manual debug helper, e.g. `kill_process.sh lp_app` to free the camera for the SDK test tools. Because the match is a substring match and the script itself runs with the name in its own argv, it may also kill its own shell when that shell's line matches; `grep -v grep` excludes only grep [INFERENCE].

## Evidence

```
$ cat oem/usr/bin/kill_process.sh   (quoted above)
PIDS=$(ps | grep "$PROCESS_NAME" | grep -v grep | awk '{print $1}')
    kill -9 $PID
$ grep -rlaE kill_process downlaods/3/dump  -> only the script itself
```

## Open questions

- Whether `lp_app` or a remote shell feature ever invokes this script dynamically by name; static grep found no caller.
