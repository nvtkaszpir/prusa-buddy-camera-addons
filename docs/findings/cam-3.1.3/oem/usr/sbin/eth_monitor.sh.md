# `eth_monitor.sh`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/eth_monitor.sh` |
| file type | `POSIX shell script, ASCII text executable` |
| size | `1073` |
| sha256 | `e8af0774dcbe42caa1ac37f1bab5899915f21ee836ce37e632e7e619eb63c15a` |
| linked libraries | `n/a` |
| origin | Vendor (camera integrator) helper script; no copyright header. [INFERENCE] written for this product line, not taken from the Rockchip SDK. |
| confidence | high |

## Summary

A small link-state daemon. Despite its name it works on any network interface. Every 2 seconds it polls `/sys/class/net/<iface>/carrier`. When the link comes up it starts the BusyBox DHCP client `udhcpc`. When the link goes down it kills that client and clears the interface's IPv4 address. On this camera it is the only thing that gets an IP address for `wlan0` in Wi-Fi client (station) mode, because `wifi_setup.sh` and `lp_app` never call `udhcpc` themselves.

## Usage

The script prints no usage text. Its only argument is the interface name:

```
eth_monitor.sh <interface>
```

- `$1`: network interface to watch, for example `wlan0` or `eth0`. It is used both as the sysfs name and in the pid and flag file names. If you leave it out, the script still runs, but it reads `/sys/class/net//carrier`, which never gives a value, so it loops forever without doing anything.
- Environment: no variables are read. The script runs `udhcpc`, `ifconfig`, `kill`, `cat`, `touch` and `sleep` from `PATH`; on this camera these are BusyBox applets (`/sbin/udhcpc -> ../bin/busybox`, the system BusyBox v1.27.2; verified read-only on the live camera, 2026-10-31).

## How it works

Line-by-line walkthrough (line numbers refer to the 47-line file):

- L3: `interface=$1`
- L5: `prev_status=""` stores the last carrier value seen, so the script only reacts when it changes.
- L6: `# udhcpc_pid=""` is a leftover comment.
- L7: `PIDFILE=/var/run/$1.pid`. `udhcpc` writes its pid here (it is started with `-p`). Example: `/var/run/wlan0.pid`.
- L8: `ETHMONITOR_FLAG=/var/run/${1}flag.pid`, for example `/var/run/wlan0flag.pid`. Despite the `.pid` suffix this is an empty marker file meaning "monitor already running".
- L9-17 `cleanup()`: if the pid file exists, it kills that pid, deletes the file and runs `ifconfig "$interface" 0.0.0.0`. **This is dead code:** nothing calls `cleanup` and there is no `trap`, so it never runs.
- L19-22, single-instance guard: if the flag file already exists, the script prints `eth monitor $interface started` and exits 0. The message is printed when another instance is *already* running. The flag file is never deleted (it lives on tmpfs `/var/run`), so the guard holds until reboot. A second instance for the same interface, for example one started by hand, exits immediately. Killing the running monitor does not remove the flag, so a restart is refused until you delete the flag file.
- L24: `touch $ETHMONITOR_FLAG`
- L26-47, main loop (never ends):
  - `sleep 2`
  - `current_status=$(cat /sys/class/net/$interface/carrier 2>/dev/null)`. This is `1` when there is a link and `0` when there is none. Reading it fails, giving an empty value, while the interface is administratively down. Empty values are ignored.
  - If the value is non-empty and differs from `prev_status`, the script saves it and then:
    - `1`: prints `Link is Up` and starts `udhcpc -i "$interface" -p "$PIDFILE" &`. No `-s` script is given, so BusyBox uses its compiled-in default script `/usr/share/udhcpc/default.script`; that file is not in the dump and was not checked on the live camera. No `-b`, `-n`, `-q` or `-t` is given, so the client keeps retrying and renewing until it is killed.
    - anything else: prints `Link is Down`. If the pid file exists it runs `kill $(cat $PIDFILE)` and `rm -f $PIDFILE`. Then it runs `ifconfig "$interface" 0.0.0.0` to remove the IPv4 address.
  - L37: an old commented-out way of finding the udhcpc pid with `ps | grep | awk`, now replaced by the `-p` pid file.

On Wi-Fi, `carrier` becomes `1` once the station has associated and authenticated. That happens after `wpa_supplicant`, started by [`wifi_setup.sh`](wifi_setup.sh.md) `sta`, reaches COMPLETED. [INFERENCE] In AP mode, carrier also becomes `1` once `hostapd` brings up the BSS, which means `udhcpc` is started on the AP interface as well (see Open questions).

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/class/net/<iface>/carrier` (read every 2 s).
- Files and paths read/written: `/var/run/<iface>flag.pid` (created, never removed); `/var/run/<iface>.pid` (written by `udhcpc -p`, read and deleted by this script). The dump, which includes runtime state in `run/`, contains `run/wlan0flag.pid` (0 bytes) and `run/wlan0.pid` (`438`), so this script was running for `wlan0` when the dump was taken.
- Network: DHCPv4 client (UDP 68 → 67, broadcast) through `udhcpc` on `<iface>`; `ifconfig <iface> 0.0.0.0` on link loss.
- Environment variables / config files: none read directly. It needs `udhcpc` and `ifconfig` in `PATH`, and itself relies on `/oem/usr/sbin` being in `PATH`, which `/etc/profile.d/RkEnv.sh` adds (sourced by `/etc/init.d/S21appinit`).

## Relevance on this camera

- **Started at boot.** [`RkLunch.sh`](../bin/RkLunch.sh.md) `network_init()` ends with `eth_monitor.sh "$interface"&`. `post_chk()` calls `network_init wlan0&`. In the dump, `network_init eth0&` is commented out; according to the RkLunch.sh report, the **live** RkLunch.sh has it enabled, so the live camera runs two monitors, one for `wlan0` and one for `eth0`.
- `network_init()` first handles the MAC address. It compares the current `HWaddr` with `/data/<iface>addr.txt`, applies the stored MAC with `ifconfig <iface> hw ether` if they differ, otherwise writes the current one. Then it runs `ifconfig <iface> up` and starts this monitor. This script itself never touches the MAC.
- No other caller: grepping the whole dump for `eth_monitor` matches only `RkLunch.sh`. `lp_app` (dump and live builds) has no `eth_monitor` or `udhcpc` strings.
- Station mode depends on it: `wifi_setup.sh sta` starts `wpa_supplicant` but the DHCP step (`check_wpa_status` → `get_ip_address` → `udhcpc`) is commented out. So `wlan0` only gets an address because this monitor sees carrier=1 and starts `udhcpc`.
- Running it by hand: for an interface that is already monitored it just prints `eth monitor <iface> started` and exits. For a new interface it starts a permanent background loop that will kill or restart `udhcpc` and clear the interface's IP whenever the link drops.

## Evidence

```
$ sha256sum eth_monitor.sh
e8af0774dcbe42caa1ac37f1bab5899915f21ee836ce37e632e7e619eb63c15a  eth_monitor.sh
$ grep -rlaE 'wifi_setup|eth_monitor|fw_version' downlaods/3/dump/
./oem/usr/bin/RkLunch.sh   ./oem/usr/sbin/lp_app (wifi_setup only)   ./oem/usr/sbin/wifi_setup.sh
$ grep -n 'eth_monitor\|network_init' oem/usr/bin/RkLunch.sh
53:    eth_monitor.sh "$interface"&
80:	#network_init eth0&
81:	network_init wlan0&
$ ls -la run/ ; cat run/wlan0.pid
-rw-r--r-- 1 ... 4 ... wlan0.pid
-rw-r--r-- 1 ... 0 ... wlan0flag.pid
438
$ cat etc/profile.d/RkEnv.sh
export HOME=/oem
export PATH=$PATH:$HOME:$HOME/bin:$HOME/usr/bin:$HOME/sbin:$HOME/usr/sbin
$ strings -n 3 bin/busybox | grep -xE 'udhcpc|killall|ifconfig|route|modprobe|insmod|rmmod|seq|awk|tr|cut|pgrep|telnetd|sleep|touch' | sort -u
awk cut ifconfig insmod killall rmmod route seq sleep telnetd touch udhcpc
```

On the live camera, md5 is identical to the dump copy (comparison supplied by the main agent).

## Open questions

- [INFERENCE] In AP mode (`wifi_setup.sh ap`) `wlan0` carrier also goes to 1, so this monitor starts `udhcpc` on the AP interface, which has the static IP `192.168.42.1`. It is not known statically whether that client ever gets a lease. If it did, the BusyBox default script would replace `192.168.42.1`. Likely no lease arrives, because `udhcpd` on the same interface does not receive the client's own raw broadcasts, leaving a `udhcpc` that keeps retrying.
- [INFERENCE] When `lp_app` switches between STA and AP, the carrier drops briefly and this script runs `ifconfig wlan0 0.0.0.0`. If that happens after `wifi_setup.sh` has set `192.168.42.1`, the AP would lose its address. Whether this race happens in practice cannot be decided statically.
- `udhcpc` is the system BusyBox v1.27.2 applet (`/sbin/udhcpc -> ../bin/busybox`, verified read-only on the live camera, 2026-10-31), but its default script `/usr/share/udhcpc/default.script` is not in the dump and was not checked on the live camera, so how it sets the route and DNS remains unverified.
- It is not verified whether `/var/run` is a symlink to `/run` on the device. The dump has only `run/`, and the expected files are there.
