# `wifi_setup.sh`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/wifi_setup.sh` |
| file type | `POSIX shell script, ASCII text executable` |
| size | `12638` |
| sha256 | `c9525288ec040ac1744f7b920ef4b9267d1ede092f6554885d1ff2d24de8c9c7` |
| linked libraries | `n/a` |
| origin | Ambarella SDK Wi-Fi script (header: `Copyright (C) 2004-2014, Ambarella, Inc.`, `2014/04/01 - [Tao Wu] modify file`), adapted by the camera vendor: `/oem/usr/etc/udhcpd.conf`, a `/tmp/langpai/hostapd` comment, `MODULE_ID=RTL8188FU`, DHCP in station mode left out |
| confidence | high |

## Summary

This script switches the Wi-Fi interface `wlan0` between two roles:

- **station (client) mode**: it writes `/tmp/config/wpa_supplicant.conf` and starts `wpa_supplicant`.
- **access-point mode**: it writes `/tmp/config/hostapd.conf`, gives the camera the address `192.168.42.1`, and starts `hostapd` plus the DHCP server `udhcpd`.

It can also tear everything down (`stop`). A Wi-Fi Direct (P2P) mode is left over from the Ambarella original. The camera application `lp_app` runs this script through `system()` whenever it changes Wi-Fi mode.

## Usage

The script's own usage text (`usages()`), verbatim:

```
usage: $0 [sta|ap|p2p] [wext|nl80211]  <SSID> <Password> [open|wpa] <Channel>
Example:
Connect To AP: 		$0 sta nl80211 <SSID>
Connect To security AP: $0 sta nl80211 <SSID> <Password>
Setup AP[Open]: 	$0 ap nl80211 <SSID> 0 open <Channel>
Setup AP[WPA]: 		$0 ap nl80211 <SSID> <Password> wpa <Channel>
Setup P2P: 		$0 p2p nl80211 <SSID>
Stop all APP(STA, AP, P2P): 	$0 stop
Notice: If you setup AP mode, WPS is enable by default. #hostapd_cli -i<interface> [wps_pbc |wps_pin any <Pin Code> ]
```

The `hostapd_cli` hint is only text; the script never runs it. `hostapd_cli` does not exist on the camera (verified read-only on the live camera, 2026-10-31), so following that hint by hand fails.

Positional arguments (L8-13):

| # | variable | meaning |
|---|---|---|
| 1 | `mode` | `sta`, `ap`, `p2p` or `stop` |
| 2 | `driver` | `wext` or `nl80211` (passed to `wpa_supplicant -D`; ignored in AP mode) |
| 3 | `ssid` | network to join (sta), network to create (ap), or P2P device name |
| 4 | `passwd` | WPA passphrase. For an open AP pass any placeholder such as `0` |
| 5 | `encryption` | AP only: `open` or `wpa` (WPA2-PSK/CCMP) |
| 6 | `channel` | AP only: 1-14; default `1` |

The usage text is partly wrong:

- WPS is **not** enabled: `eap_server=1` is commented out.
- "Connect To AP" with only an SSID still produces a WPA-PSK config with an empty passphrase (see below).

Environment: the script exports `P2P_AUTO_CONNECT=yes` and `P2P_CONNECT_PREFIX=amba`, which only matter for the P2P event script. It reads no environment variables of its own. It needs `wpa_supplicant`, `wpa_cli`, `hostapd`, `udhcpd`, `udhcpc`, `ifconfig`, `route`, `killall`, `seq` and `awk` in `PATH`. On the camera `wpa_supplicant` (`/usr/bin/wpa_supplicant`, 458644 bytes, `wpa_supplicant v2.6`) and `wpa_cli` (`/usr/bin/wpa_cli`, 50784 bytes) exist, and `udhcpc` is the system BusyBox v1.27.2 applet (`/sbin/udhcpc -> ../bin/busybox`) (verified read-only on the live camera, 2026-10-31).

How `lp_app` calls it (format strings from the dump `lp_app`):

```
%s ap nl80211 "%s" "%s" wpa %d        -> wifi_setup.sh ap nl80211 "<ssid>" "<pwd>" wpa <best_channel>
%s sta nl80211 "%s" "%s"              -> wifi_setup.sh sta nl80211 "<ssid>" "<psk>"
%s stop                               -> wifi_setup.sh stop
```

## How it works

Line numbers refer to the 515-line file.

**Constants (L15-58)**

| name | value | notes |
|---|---|---|
| `DEVICE` | `wlan0` | the only interface this script handles |
| `DIR_CONFIG` | `/tmp/config` | tmpfs, so configs are rebuilt on every boot |
| `frequency` | `2412` | |
| `chip` | `rtl8188` | |
| `BCMDHD_CONFIG` | `/tmp/config/dhd.conf` | |
| `CTRL_INTERFACE` | `/var/run/wpa_supplicant` | |
| `CONFIG` | `/tmp/config/wpa_supplicant.conf` | |
| `WPA_LOG` | `/var/log/wpa_supplicant.log` | |
| `NO_SCAN` | `1` | |
| `KILL_NUM_MAX` | `10` | unused |
| `CONNECT_NUM_MAX` | `100` | |
| `HOSTAP_CTRL_INTERFACE` | `/var/run/hostapd` | |
| `HOST_CONFIG` | `/tmp/config/hostapd.conf` | |
| `DEFAULT_CHANNEL` | `1` | |
| `HOST_MAX_STA` | `5` | |
| `IP_CONFIG` | `/tmp/config/ip.conf` | only ever deleted |
| `LOCAL_IP` | `192.168.42.1` | |
| `LOCAL_NETMASK` | `255.255.255.0` | |
| `DHCP_IP_START`, `DHCP_IP_END` | `192.168.2.2`, `192.168.2.20` | unused leftovers from the commented-out dnsmasq; the real pool comes from `udhcpd.conf` |
| `P2P_CONFIG` | `/tmp/config/p2p.conf` | |
| `WPA_ACTION` | `/usr/local/bin/wpa_event.sh` | not present in the dump |

**Wi-Fi module detection (L58-63):** `MODULE_ID=RTL8188FU` by default. It becomes `BCMDHD` if `/sys/module/bcmdhd` exists, or `RTL8189ES` if `/sys/module/8189es` exists. This camera loads `8188fu.ko`, via `/oem/usr/ko/insmod_wifi.sh` (`insmod cfg80211.ko`, `insmod 8188fu.ko`), so `MODULE_ID` stays `RTL8188FU`.

**Functions**

- `usages()` (L68): prints the help text above.
- `close_fd()` (L81): `cd /proc/$$/fd`, prints `$PWD`, then `exec N>&-` for N = 3..100. This closes file descriptors inherited from the caller. [INFERENCE] Because `lp_app` runs the script through `system()`, this stops `wpa_supplicant`, `hostapd` and `udhcpd`, which are daemonised from here, from inheriting `lp_app`'s sockets and files (for example the RTSP listener on :554). Side effect: the working directory becomes `/proc/<pid>/fd`, which is why the later `-----------PWD=` log lines show that path.
- `check_param()` (L94): calls `close_fd`, then validates the arguments:
  - `mode` must be `sta`, `ap`, `p2p` or `stop`; `driver` must be `wext` or `nl80211`. On a bad value it prints `Please Select Mode ...` or `Please Select Driver ...` and exits 1.
  - For `ap`: `encryption` must be `open` or `wpa`.
  - For `ap`: a channel above 14 or below 1 is reset to 1 (`Your Channel is wrong(1 ~ 13), using Channl 1 by default.`). An empty channel also falls back to 1.
- `check_wpa_supplicant()` (L124): parses `wpa_supplicant -v`. Its only caller is commented out, so `wpa_supplicant_version` stays `unknown`.
- `kill_apps()` (L133): `killall -9` on each argument. A retry loop around it is commented out.
- `generate_bcmdhd_conf()` and `generate_driver_conf()` (L152, L158): write `roam_cache_ssid` and `roam_cache_channel` to `/tmp/config/dhd.conf`, only for Broadcom. Not used here: `generate_wpa_conf` is their only caller, and it is never called.
- `WPA_SCAN()` (L166): starts a temporary `wpa_supplicant`, runs `wpa_cli scan`, waits 3 s, reads `scan_result`, kills `wpa_supplicant`, then `rm -r /var/run/wpa_supplicant`. Only reached from `generate_wpa_conf`, so unused.
- `generate_wpa_hidden_conf()` (L182), **the one used for `sta`**. It writes:
  ```
  ctrl_interface=/var/run/wpa_supplicant
  network={
  scan_ssid=1
  ssid="<ssid>"
  key_mgmt=WPA-PSK
  psk="<passwd>"
  }
  ```
  `scan_ssid=1` means directed probes, so hidden SSIDs work. Only WPA/WPA2-PSK is supported; open and WEP networks are not handled. Nothing is escaped: a `"` in the SSID or password breaks the file. The passphrase is stored in plaintext on tmpfs.

- `generate_wpa_conf()` (L194), unused (its call is commented out at L497). This is the smarter Ambarella version: it scans, matches the SSID, works out the channel from the frequency, and picks `proto` (WPA or WPA2), `pairwise` (CCMP or TKIP), WEP (`wep_key0`) or open (`key_mgmt=NONE`). It also writes `disabled=1` because `NO_SCAN=1`.
- `start_wpa_supplicant()` (L268): runs `ifconfig wlan0 up`, then both branches of the version check run the same command:
  `wpa_supplicant -Dnl80211 -iwlan0 -c/tmp/config/wpa_supplicant.conf -P /var/run/wlan0_wpa_flag.pid -B`
  followed by `wpa_cli -p/var/run/wpa_supplicant -i wlan0 select_network 0`. A debug variant logging to `/var/log/wpa_supplicant.log` with `-ddd -t` is commented out.
- `get_ip_address()` (L283): `udhcpc -iwlan0`. Its only caller is `check_wpa_status`.
- `check_wpa_status()` (L289): up to 101 polls of `wpa_cli status` until `wpa_state=COMPLETED`. Then it runs `udhcpc` and prints `>>>wifi_setup OK<<<`; otherwise it prints `>>>wifi_setup failed, password may be incorrect or ap not in range<<<`. **Its call is commented out (L502)**, so the script returns as soon as `wpa_supplicant` is daemonised. Watching the connection is left to `lp_app`, which polls the same `wpa_cli ... status | grep wpa_state` command. Getting an address is left to [`eth_monitor.sh`](eth_monitor.sh.md).
- `generate_hostapd_conf()` (L321): if `/tmp/config/hostapd.conf` already exists it is reused, but `check_param`/`clear_config` always delete it first when there are more than two arguments. It writes:
  ```
  interface=wlan0
  ctrl_interface=/var/run/hostapd
  beacon_int=100
  preamble=0
  ssid=<ssid>
  max_num_sta=5
  channel=<channel>
  # if encryption == wpa:
  wpa=2
  wpa_pairwise=CCMP
  wpa_passphrase=<passwd>
  wpa_key_mgmt=WPA-PSK
  ```
  For `MODULE_ID=RTL8189ES` it adds `driver=nl80211`, `hw_mode=g`, `ieee80211n=1` and `ht_capab`. The Realtek 8188FU block tests `[ ${MODULE_ID} == "8188FU" ]`, but the default is `RTL8188FU`, **so the test never matches**. As a result `hw_mode=g`, `wme_enabled=1` and `wpa_group_rekey=86400` are never written for this camera's chip. [INFERENCE] `hostapd` then uses its defaults: `driver=nl80211`, and `hw_mode=g` in recent hostapd versions.

- `modprobe_driver()` and `modprobe_rm_driver()` (L375, L447): load or unload `usb8xxx` (rtl8801) or `insmod /mnt/flash/8189es.ko` / `rmmod 8189es`. Only `p2p` calls `modprobe_driver`; the other call sites are commented out. Neither path exists on this camera.
- `start_hostapd_ap()` (L387):
  - `ifconfig wlan0 up`
  - `ifconfig wlan0 192.168.42.1`
  - `route add default netmask 255.255.255.0 gw 192.168.42.1`
  - `hostapd -B /tmp/config/hostapd.conf`; earlier paths `/mnt/flash/hostapd` and `/tmp/langpai/hostapd` are commented out
  - `mkdir -p /var/lib/misc`
  - `udhcpd /oem/usr/etc/udhcpd.conf`
  - prints `HostAP Setup Finished.`
- `generate_wpa_p2p_conf()` (L414): device name = SSID, or `amba-<last 7 hex digits of the MAC>`. The MAC is taken from `ifconfig wlan0 | grep HWaddr`, colons removed, `cut -c 6-`, lower-cased. This is the only MAC handling in the script. Writes `device_type=10-0050F204-5` and `config_methods=display push_button keypad`.
- `start_wpa_supplicant_p2p()` (L433): `wpa_supplicant -iwlan0 -c/tmp/config/p2p.conf -D<driver> -f/var/log/wpa_supplicant.log -B`, then `wpa_cli -a /usr/local/bin/wpa_event.sh` (if that file is executable), `p2p_set ssid_postfix "_AMBA"`, `p2p_find`.
- `stop_wifi_app()` (L457): `killall -9 NetworkManager wpa_supplicant hostapd udhcpd udhcpc`, then `rm -rf /var/run/wlan0_wpa_flag.pid`. This kills **every** `udhcpc`, including the one started by `eth_monitor.sh` (and one on `eth0`, if present).
- `clear_config()` (L464): deletes `wpa_supplicant.conf`, `hostapd.conf`, `p2p.conf` and `ip.conf` in `/tmp/config`.

**Main (L473-515)**

1. No arguments: print usage, exit 1.
2. Exactly `stop`: `clear_config`, `stop_wifi_app`, `ifconfig wlan0 down`, exit 0.
3. More than 2 arguments: `check_param` (which also runs `close_fd`) and `clear_config`. With only 1 or 2 arguments (for example `sta nl80211`) no validation runs and no old config is removed.
4. `sta`: `generate_wpa_hidden_conf` → `start_wpa_supplicant`. The calls to `modprobe_driver`, `generate_wpa_conf`, `check_wpa_supplicant` and `check_wpa_status` are commented out.
5. `ap`: computes `freq=$(($channel*5 +2407))`, which is never used → `generate_hostapd_conf` → `start_hostapd_ap`.
6. `p2p`: `generate_wpa_p2p_conf` → `modprobe_driver` → `start_wpa_supplicant_p2p`.
7. Anything else: calls `usage`, which does not exist (the function is `usages`). The shell prints `usage: not found` and the script ends with that command's status, 127. In practice this branch can only be reached with 1-2 arguments, because `check_param` already rejects bad modes when more than 2 arguments are given.

**AP-mode DHCP server** (`/oem/usr/etc/udhcpd.conf`, comments stripped):

```
start           192.168.42.20
end             192.168.42.254
interface       wlan0
remaining       yes
lease_file      /var/lib/misc/udhcpd.leases
pidfile /var/run/udhcpd.pid
option  subnet  255.255.255.0
opt     router  192.168.42.1
option  domain  local
option  lease   864000
```

Clients get `192.168.42.20`–`.254/24`, with the camera (`192.168.42.1`) as gateway and a 10-day lease. No DNS option is set.

## Interfaces touched

- Device nodes / sysfs / procfs: `/sys/module/bcmdhd`, `/sys/module/8189es` (existence checks); `/proc/$$/fd` (cwd, fd close loop).
- Files and paths read/written:
  - written: `/tmp/config/wpa_supplicant.conf`, `/tmp/config/hostapd.conf`, `/tmp/config/p2p.conf`, `/tmp/config/dhd.conf`
  - deleted: `/tmp/config/ip.conf`, `/var/run/wlan0_wpa_flag.pid` (written by `wpa_supplicant -P`), `/var/run/wpa_supplicant` (only in the unused `WPA_SCAN`)
  - created: `/var/lib/misc/` (udhcpd lease file `/var/lib/misc/udhcpd.leases`)
  - read: `/oem/usr/etc/udhcpd.conf`
  - control sockets: `/var/run/wpa_supplicant/`, `/var/run/hostapd/`
  - only on unused paths: `/var/log/wpa_supplicant.log`, `/usr/local/bin/wpa_event.sh`, `/mnt/flash/8189es.ko`
- Network:
  - interface `wlan0` only
  - STA: WPA/WPA2-PSK client via `wpa_supplicant` (nl80211), with hidden-SSID probing
  - AP: `hostapd` WPA2-PSK/CCMP (or open), up to 5 clients, chosen channel, static `192.168.42.1/24` plus a default route through itself, `udhcpd` DHCP server (UDP 67) handing out `192.168.42.20-254`
  - `stop`: interface down
- Environment variables / config files: exports `P2P_AUTO_CONNECT=yes` and `P2P_CONNECT_PREFIX=amba`. Uses `PATH`, which needs `/oem/usr/sbin` (for `hostapd`, `udhcpd` and the script itself) via `/etc/profile.d/RkEnv.sh`. Config inputs: `/oem/usr/etc/udhcpd.conf`. SSID and password come from `lp_app`, which keeps the AP credentials in `/userdata/xhr_config.ini` `[wifi_ap]` (`ssid`, `pwd`) [INFERENCE: mapping of ini keys to these arguments].

## Relevance on this camera

- **Not started by any boot script.** Grepping the dump for `wifi_setup` matches only the script itself and `lp_app`. [`RkLunch.sh`](../bin/RkLunch.sh.md) only brings `wlan0` up and starts [`eth_monitor.sh`](eth_monitor.sh.md).
- **Called by `lp_app`** (`xhr_platform_device_service/lp_peripheral_wifi/`):
  - `lp_wifi_ap_mode.cpp`, class `NSLpTech::NSLpTools::LpWifiApMode`: `sprintf(buf, "%s ap nl80211 \"%s\" \"%s\" wpa %d", ...)`, where the channel comes from a best-channel scan (`wifi_ap_mode best_channel:`; `iwlist wlan0 scan | grep Channel > /tmp/wifi_env_channel`). It reports clients with `iw dev wlan0 station dump > /tmp/sta`.
  - `lp_wifi_sta_mode.cpp`, class `LpWifiAStaMode`: `"%s sta nl80211 \"%s\" \"%s\""`. It checks `/var/run/wlan0_wpa_flag.pid` and polls `popen("wpa_cli -p /var/run/wpa_supplicant -iwlan0 status | grep wpa_state")`, parsing it with `sscanf("wpa_state=%s")` and comparing against `COMPLETED`.
  - `LpWifiMode::startWifi` / stop: `"%s stop"`.
  - The first `%s` is [INFERENCE] the string `wifi_setup.sh`, found via `PATH`. That literal is at file offset `0x254ca4` and is loaded from a static initialiser at `0x625a8`.
  - Disassembly shows the AP function calls `sprintf` (PLT `0x1bd08`) with the AP format, then a helper at `0x7541c` that calls `system` (PLT `0x1c17c`).
- Live `lp_app` (newer build) contains the same strings: `wifi_setup.sh`, the `ap` and `stop` formats, and the `sta` format split as ` sta nl80211 "` / `" "`. It also reads `/sys/class/net/wlan0/address`. The script itself is md5-identical on the live camera.
- Evidence it has run: the dump's `tmp/config/wpa_supplicant.conf` (118 bytes) has exactly the `generate_wpa_hidden_conf` layout, and `run/wlan0_wpa_flag.pid` = `375`. **That file contains the owner's home Wi-Fi SSID and passphrase in plaintext** (values redacted here: `ssid="…[redacted]"`, `psk="…[redacted]"`). `/etc/wpa_supplicant.conf` in the dump is a separate file with `ap_scan=1`/`update_config=1` that this script does not use (it also contains SSID/PSK values, redacted).
- Running it by hand: `wifi_setup.sh stop` drops Wi-Fi (and kills every `udhcpc`, NetworkManager, hostapd and udhcpd), which cuts off a network session. `ap`/`sta` reconfigure `wlan0` without telling `lp_app`, so `lp_app`'s own state machine may later undo the change [INFERENCE].
- Security notes:
  - [INFERENCE] `lp_app` puts the SSID and password inside double quotes in a `system()` command line, so `$`, `` ` `` or `"` in them would be interpreted by the shell. Whether `lp_app` sanitises these values cannot be seen statically.
  - The script writes the passphrases unescaped into the config files.

## Evidence

```
$ file eth_monitor.sh wifi_setup.sh ; sha256sum wifi_setup.sh
wifi_setup.sh:  POSIX shell script, ASCII text executable
c9525288ec040ac1744f7b920ef4b9267d1ede092f6554885d1ff2d24de8c9c7  wifi_setup.sh
$ strings -n 4 -t x oem/usr/sbin/lp_app | grep -E 'wifi_setup|nl80211|wpa_|hostapd|station dump'
 25374a iw dev wlan0 station dump > /tmp/sta
 25376f /tmp/config/hostapd.conf
 253788 xhr_platform_device_service/lp_peripheral_wifi/lp_wifi_ap_mode.cpp
 2537e7 %s ap nl80211 "%s" "%s" wpa %d
 25386e %s stop
 2538c0 wpa_cli -p /var/run/wpa_supplicant -iwlan0 status | grep wpa_state
 253910 xhr_platform_device_service/lp_peripheral_wifi/lp_wifi_sta_mode.cpp
 25396b /var/run/wlan0_wpa_flag.pid
 253987 %s sta nl80211 "%s" "%s"
 254ca4 wifi_setup.sh
$ llvm-nm-14 -D lp_app | grep -wE 'system|popen'
         U popen
         U system
# literal-pool xrefs (vaddr = file offset + 0x10000): ap fmt <- 0x6003c, stop fmt <- 0x60154,
# sta fmt <- 0x60520, wifi_setup.sh <- 0x625a8
$ llvm-objdump -d ... --start-address=0x5ff40   (PLT resolved via .rel.plt order)
 5ff74: ldr r1,[pc,#192] @0x6003c ; 5ff88: bl 0x1bd08 (sprintf) ; 5ffd8: bl 0x7541c
$ llvm-objdump -d ... --start-address=0x7541c
 75440: bl 0x1c17c (system)
$ cat oem/usr/ko/insmod_wifi.sh | grep insmod
insmod cfg80211.ko
insmod 8188fu.ko
$ ls run/ ; cat run/wlan0_wpa_flag.pid
wlan0_wpa_flag.pid wpa_supplicant/ ...   375
$ find downlaods/3/dump -name wpa_supplicant -o -name wpa_cli
./run/wpa_supplicant        (control dir only; binaries not in dump)
```

## Open questions

- Resolved: `wpa_supplicant` (`/usr/bin/wpa_supplicant`, `wpa_supplicant v2.6`) and `wpa_cli` (`/usr/bin/wpa_cli`) exist on the camera, and `udhcpc` is the system BusyBox v1.27.2 applet (`/sbin/udhcpc -> ../bin/busybox`) (verified read-only on the live camera, 2026-10-31). `NetworkManager` is very likely absent; its `killall` is just a harmless failure.
- Because of the `"8188FU"` vs `RTL8188FU` mismatch, `hostapd.conf` has no explicit `hw_mode`, `wme_enabled` or `driver`. The `hostapd` defaults in `/oem/usr/sbin/hostapd` (see the separate hostapd report) decide the PHY mode [INFERENCE: 802.11g, nl80211].
- `route add default ... gw 192.168.42.1` in AP mode makes the camera route all non-local traffic to itself. Whether `lp_app` removes or overrides this when going back to STA is not visible statically.
- Interaction with `eth_monitor.sh` in AP mode (a `udhcpc` started on the AP interface, `ifconfig wlan0 0.0.0.0` on carrier loss) is described in the [eth_monitor.sh report](eth_monitor.sh.md); its effect at runtime is unconfirmed.
- Exactly how `lp_app` maps `/userdata/xhr_config.ini` `[wifi_ap] ssid/pwd` and the user's home network credentials to the arguments has not been traced through the disassembly.
