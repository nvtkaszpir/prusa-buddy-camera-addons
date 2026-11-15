# `iw`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/iw` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `194872` |
| sha256 | `a7eb537fc4c6082a6f9d4ea56ed55d528a0312f3bd7a84fde1f350d6fbe145c4` |
| linked libraries | `libnl-genl-3.so.200, libnl-3.so.200, libc.so.0, ld-uClibc.so.1` |
| origin | upstream `iw` 5.19 (kernel.org nl80211 configuration utility), stock build, cross-compiled for uClibc armhf |
| confidence | high |

## Summary

`iw` is the standard nl80211/cfg80211 command-line tool for configuring wireless devices, version 5.19. `lp_app` calls it through a shell for two things. It reads the station's signal strength with `iw dev wlan0 link`, and in AP mode it checks whether any client is associated with `iw dev wlan0 station dump`. The binary is md5-identical on the running camera.

## Usage

The embedded usage text, verbatim (`%s` is `argv[0]` or the version):

```
Usage:	%s [options] command
Options:
	--debug		enable netlink debugging
	--version	show version (%s)
Commands:
Commands that use the netdev ('dev') can also be given the
'wdev' instead to identify the device.
You can omit the 'phy' or 'dev' if the identification is unique,
e.g. "iw wlan0 info" or "iw phy0 info". (Don't when scripting.)
Do NOT screenscrape this tool, we don't consider its output stable.
```

`iw --version` prints `iw version %s`. `%s` is `5.19`, the only version-like string in `.rodata` besides the HE guard-interval values `0.8`, `1.6` and `3.2`.

The command table was rebuilt from the `__cmd` section (vaddr `0x4f16c`, 146 `struct cmd *` entries; the 121 entries with handlers are listed). It is the full upstream 5.19 set:

- Global: `help [command]`, `event [-t|-T|-r] [-f]`, `list`/`phy`, `dev`, `commands`, `features`, `reg get`, `reg set <ISO/IEC 3166-1 alpha2>`, `reg reload`.
- `dev <devname>` commands:
  - `info`, `del`, `interface add`
  - `link`
  - `scan [...]`, `scan dump [-u]`, `scan trigger`, `scan abort`, `scan sched_start`, `scan sched_stop`
  - `station dump [-v]`, `station get <MAC>`, `station del <MAC>`, `station set <MAC> {plink_action|vlan|mesh_power_mode|airtime_weight|txpwr}`
  - `survey dump [--radio]`
  - `connect [-w] <SSID> ...`, `disconnect`, `auth ...`
  - `ibss join/leave`, `mesh join/leave`, `mpath ...`, `mpp ...`, `ocb join/leave`
  - `set type|channel|freq|txpower|power_save|bitrates|monitor|4addr|noack_map|mcast_rate|meshid|mesh_param|peer|tidconf`, `get power_save|mesh_param`
  - `switch channel/freq`, `cac`, `cqm rssi`, `offchannel`, `roc start`
  - `ap start/stop`, `ftm get_stats/start_responder`, `measurement ftm_request`
  - `vendor send/recv/recvbin`, `mgmt dump`
- `phy <phyname>` commands: `info`, `channels`, `interface add`, `reg get`, `set name|channel|freq|frag|rts|retry|netns|coverage|distance|txpower|antenna|txq|sar_specs`, `get txq`, `wowlan enable/disable/show`, `coalesce enable/disable/show`, `hwsim getps/setps/stopqueues/wakequeues`.
- `wdev <idx>` commands: `p2p start/stop`, `nan start/stop/config/add_func/rm_func`.

## How it works

- At startup it opens a generic netlink socket with `nl_socket_alloc`, `genl_connect` and `genl_ctrl_resolve("nl80211")`. On failure it prints `Failed to connect to generic netlink.` or `nl80211 not found.`
- It finds the command in the `__cmd` table and checks the identification type (`phy`/`dev`/`wdev`). It resolves names to indexes with `if_nametoindex` or by reading `/sys/class/ieee80211/%s/index`.
- It builds an nl80211 message (`genlmsg_put`, `nla_put*`), sends it (`nl_send_auto_complete`) and handles replies through `nl_cb_set` callbacks and `nl_recvmsgs`.
- Results are printed as text (`fprintf`/`printf`). `event` uses `nl_socket_add_membership` to listen for nl80211 multicast events.
- It does not depend on libnl-route. The only libraries are libnl-3, libnl-genl-3 and uClibc.

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/class/ieee80211/%s/index`; generic netlink family `nl80211` (cfg80211, provided here by `cfg80211.ko` and the Realtek `8188fu.ko`, kernel `5.10.110`).
- Files and paths read/written: config files only for commands that take them (`coalesce enable <config-file>`, `measurement ftm_request <config-file>`, `vendor send <filename>`). The camera's own uses redirect output to `/tmp/sta` (via `lp_app`'s shell command).
- Network: none (netlink only). It can trigger 802.11 scans and connections on `wlan0`.
- Environment variables / config files: none found.

## Relevance on this camera

`iw` is not started at boot. No init script references it; [`RkLunch.sh`](../bin/RkLunch.sh.md) and [`wifi_setup.sh`](wifi_setup.sh.md) do not use it. Its only caller is [`lp_app`](lp_app.md), with two command lines. Both are present in the dump build and in the newer live build.

1. **Signal-strength probe** (`xhr_tools/Util/lp_system_tool.cpp` area). The function at `0x74da4` does the following:
   - builds `"iw dev " + <ifname> + " link"` with `std::string` `append`;
   - runs it with `popen(..., "r")` (logging `popen failed` on error) and reads the output with `fgets`, then `pclose`;
   - finds `signal:` and parses the number after it with `std::istringstream >> string >> int`.

   The result is the current RSSI in dBm of the associated AP in station mode.

2. **AP client detection** (`lp_wifi_ap_mode.cpp`). The function ending at `0x5fee0` does the following:
   - runs `system("iw dev wlan0 station dump > /tmp/sta")` through the logging wrapper `0x7541c`;
   - calls `stat("/tmp/sta")` and returns `st_size != 0`.

   In practice it means "at least one phone or computer is associated with the camera's setup AP".

Running `iw` by hand is harmless for read-only commands (`dev`, `link`, `station dump`, `scan dump`). Commands like `set type`, `disconnect`, `scan trigger` or `reg set` change the radio and can disturb `lp_app`'s Wi-Fi handling.

## Evidence

```
$ file iw ; sha256sum iw ; stat -c %s iw
ELF 32-bit LSB executable, ARM ... stripped
a7eb537fc4c6082a6f9d4ea56ed55d528a0312f3bd7a84fde1f350d6fbe145c4  194872
$ readelf -d iw | grep NEEDED
libnl-genl-3.so.200 libnl-3.so.200 libc.so.0 ld-uClibc.so.1
$ strings -n 3 iw | grep -nE '^[0-9]+\.[0-9]+$'
222:0.8  223:1.6  224:3.2  2471:5.19
$ strings -n 3 iw | grep -n 'iw version'
988:iw version %s
$ readelf -S -W iw | grep __cmd
[24] __cmd PROGBITS 0004f16c 02f16c 000248
(Python: parsed 146 struct cmd entries -> name/args/parent, e.g. ('dev','station dump','[-v]'), ('dev','link',''))
$ strings -n 4 lp_app | grep -E '^iw dev'
iw dev wlan0 station dump > /tmp/sta
iw dev 
lp_app 0x74dd8 'iw dev ' + ifname + ' link' -> popen -> fgets -> find("signal:") -> istringstream >> int
lp_app 0x5feb4 system-wrapper("iw dev wlan0 station dump > /tmp/sta"); 0x5fec0 stat("/tmp/sta"); return st_size!=0
```

## Open questions

- Which interface name `lp_app` passes to the `iw dev <if> link` probe. `wlan0` is the only Wi-Fi interface name in the strings [INFERENCE].
- What `lp_app` does with the parsed signal value (UI, cloud telemetry or reconnect logic) is not traced here; see the `lp_app` reports.
- Whether the `8188fu` driver fills in the `signal:` field in `iw ... link` output is not confirmed statically.
