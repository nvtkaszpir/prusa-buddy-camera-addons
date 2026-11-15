# `hostapd`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/hostapd` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `680436` |
| sha256 | `8be1f0410b88a02c0b76da37bdeb50dd41d22298b1c6a81adbdd30231e015a10` |
| linked libraries | `libnl-3.so.200, libnl-genl-3.so.200, libnl-route-3.so.200, libc.so.0, ld-uClibc.so.1` |
| origin | upstream hostapd 2.10 (w1.fi, Jouni Malinen), cross-built for uClibc armhf by the camera SDK; reduced feature set (WPA/WPA2-PSK only, no WPS/EAP methods/RADIUS/SAE) |
| confidence | high |

## Summary

The standard Linux user-space IEEE 802.11 access-point daemon, version 2.10. On the camera, `wifi_setup.sh ap ...` runs it to turn `wlan0` (Realtek RTL8188FU, `8188fu.ko`) into a Wi-Fi access point, normally WPA2-PSK/CCMP. `lp_app` uses that AP mode for setup and pairing. The binary is md5-identical on the running camera.

## Usage

The embedded help text, verbatim:

```
hostapd v%s
User space daemon for IEEE 802.11 AP management,
IEEE 802.1X/WPA/WPA2/EAP/RADIUS Authenticator
Copyright (c) 2002-2022, Jouni Malinen <j@w1.fi> and contributors
usage: hostapd [-hdBKtv] [-P <PID file>] [-e <entropy file>] \
         [-g <global ctrl_iface>] [-G <group>]\
         [-i <comma-separated list of interface names>]\
         <configuration file(s)>
options:
   -h   show this usage
   -d   show more debug messages (-dd for even more)
   -B   run daemon in the background
   -e   entropy file
   -g   global control interface path
   -G   group for control interfaces
   -P   PID file
   -K   include key data in debug messages
   -f   log output to debug file instead of stdout
   -i   list of interface names to use
   -s   log output to syslog instead of stdout
   -S   start all the interfaces synchronously
   -t   include timestamps in some debug messages
   -v   show hostapd version
```

`%s` is filled with the version string `2.10`, which sits directly before `hostapd v%s` in `.rodata`. The getopt string is `b:Bde:f:hi:KP:sSTtu:vg:G:`. It also accepts the upstream options `-b`, `-T` and `-u`, which have no help line here. The help lists `-f` and `-s`, so the build has file and syslog debug output (upstream `CONFIG_DEBUG_FILE`/`CONFIG_DEBUG_SYSLOG`).

The options the camera uses:

- `-B`: daemonise. `wifi_setup.sh` runs `hostapd -B /tmp/config/hostapd.conf`.
- `<configuration file>`: the generated `/tmp/config/hostapd.conf`.

## How it works

This is upstream hostapd 2.10 code. The build features below come from the strings and imports.

- **Driver backends.** The `wpa_drivers[]` pointer table at vaddr `0x98470` is `{ nl80211, hostap, NULL }`. The parser treats that as the struct table described below. `nl80211` comes first, so it is the default when `driver=` is missing. The nl80211 driver uses libnl through the imports `genl_connect`, `genl_ctrl_resolve`, `nl_socket_alloc`, `nl_recvmsgs` and `nla_*`, and through 558 `nl80211: ...` log strings. The legacy Host AP driver is also built in: `/proc/net/hostap/%s/...` and `hostap: Set generic IE`.
- **libnl-route use.** `rtnl_link_add`, `rtnl_link_set_type`, `rtnl_link_vlan_set_id` and `rtnl_link_delete` create VLAN interfaces through netlink (dynamic VLAN; the config keys `dynamic_vlan` and `vlan_file` are present). `rtnl_neigh_*` handles bridge neighbour entries for proxy ARP (`nl80211: bridge must be set to delete an ip neigh`).
- **Key management that is supported.** The `wpa_key_mgmt` parser strings are `WPA-EAP`, `FT-PSK`, `FT-EAP`, `WPA-PSK-SHA256`, `WPA-EAP-SHA256` and `OSEN`. `WPA-PSK` and `SAE` are not separate strings because the linker merged them into longer strings such as `WPA2-PSK+WPA-PSK` and `FT-SAE`. The `wpa_passphrase`, `wpa_psk`, `wpa_pairwise`, `rsn_pairwise`, `ieee80211w` and `beacon_prot` keys are present, so the build supports WPA/WPA2-PSK with CCMP/TKIP/GCMP, 802.11w PMF and 802.11r FT (`mobility_domain`, `r1_key_holder`, `ft_over_ds`).
- **WPA3-SAE: not built** [INFERENCE from absence]. The `sae_groups`, `sae_pwe` and `sae_password` keys exist, but those parsers are present in every build. None of the `SAE: ...` runtime log strings from upstream `sae.c` exist. There is no EC or bignum crypto: no libcrypto/libssl is linked, and no OpenSSL or wolfSSL strings are present. Without that crypto, SAE cannot be compiled. OWE (`owe_groups`) and DPP config keys are also missing. The `OWE`/`DPP` strings that do appear come only from the generic key-management name table.
- **WPS: not built.** There is no `wps_state` key and no `WPS_PBC`/`WPS_PIN` control commands. `hostapd_cli` does not exist on the camera (verified read-only on the live camera, 2026-10-31), so the `hostapd_cli` hint in `wifi_setup.sh`'s `usages()` cannot be followed. That text also says "WPS is enable by default", which is wrong for this binary.
- **EAP server and RADIUS: not usable.** The EAP state-machine core logs (`EAP: building EAP-Request ...`) are present. There is no `eap_server` or `eap_user_file` key, and no method names such as `MD5`, `TLS`, `PEAP` or `TTLS`. The RADIUS client keys `auth_server_addr` and `acct_server_addr` are missing. In practice this is a PSK-only authenticator.
- **802.11 PHY features.** The keys `ieee80211n`, `ht_capab`, `ieee80211ac`, `vht_capab`, `ieee80211ax` and `he_su_beamformer` are present. ACS is built in (`acs_num_scans`, `ACS: ...`, `Using internal ACS for hw_mode=any`). Also present: HS2.0/Interworking (`hs20`, `interworking`), `multi_ap`, WNM, and TDLS strings.
- **Control interface.** UNIX datagram socket: `ctrl_iface bind(PF_UNIX) failed: %s` and `ctrl_iface exists and seems to be in use - cannot override it`. The command strings include `STATUS-DRIVER`, `MIB`, `STA-FIRST`, `STA-NEXT`, `ATTACH`, `DETACH`, `GET_CONFIG`, `SET`, `GET`, `ENABLE`, `DISABLE`, `RELOAD`, `RELOAD_WPA_PSK`, `CHAN_SWITCH`, `DEAUTHENTICATE`, `DISASSOCIATE`, `PMKSA_FLUSH`, `TERMINATE`, `ACCEPT_ACL`, `DENY_ACL` and `INTERFACES`. Events include `AP-ENABLED`, `AP-STA-CONNECTED %s%s%s` and `CTRL-EVENT-TERMINATING`.
- **Crypto and randomness.** No crypto library is linked, so the build uses hostapd's internal crypto. It seeds randomness from its own pool (`random from internal pool`). With `-e`, it also uses an entropy file.
- **Process control.** It forks into the background with `daemon`/`fork` and reports through `syslog`/`openlog`. `execv` and `waitpid` are imported.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/sys/class/net/%s/phy80211`
  - `/sys/class/rfkill/rfkill%d/device`
  - `/sys/class/net/%s/brport/bridge`
  - `/sys/class/net/%s/master`
  - `/sys/class/net/%s/brport/%s`
  - `/sys/devices/virtual/net/%s/bridge/multicast_snooping`
  - `/proc/sys/net/ipv%d/conf/%s/%s`
  - `/proc/sys/net/ipv4/conf/%s/drop_unicast_in_l2_multicast`
  - `/proc/sys/net/ipv4/conf/%s/drop_gratuitous_arp`
  - `/proc/sys/net/ipv6/conf/%s/drop_unsolicited_na`
  - `/proc/net/hostap/...` (hostap driver only)
  - Netlink: generic netlink `nl80211` and `NETLINK_ROUTE`
  - ioctls on `wlan0`
- Files and paths read/written:
  - Config: `/tmp/config/hostapd.conf`, generated by `wifi_setup.sh`.
  - Control socket directory: `/var/run/hostapd`, from `ctrl_interface=/var/run/hostapd` in the generated config. The socket is `/var/run/hostapd/wlan0`.
  - Optional: `accept_mac_file` and `deny_mac_file` (not used by the camera config).
- Network:
  - IEEE 802.11 AP on `wlan0`. The channel comes from `lp_app`'s "best channel" calculation, with 1 as the default.
  - EAPOL 4-way handshake (WPA2-PSK).
  - No IP sockets of its own apart from the UNIX control socket.
- Environment variables / config files: `/tmp/config/hostapd.conf`. Environment variables: none found by name in the strings. `setenv`/`unsetenv` are imported, probably through upstream's `os_setenv`/`os_unsetenv` wrappers [INFERENCE].

## Relevance on this camera

hostapd is **not started at boot**. Neither `etc/init.d/*` nor `/oem/usr/etc/init.d/S10ntp` references it, and neither does [`RkLunch.sh`](../bin/RkLunch.sh.md). Its only caller in the dump is [`wifi_setup.sh`](wifi_setup.sh.md), which `lp_app` runs when it switches to AP mode.

1. In [`lp_app`](lp_app.md), the AP-mode function (`xhr_platform_device_service/lp_peripheral_wifi/lp_wifi_ap_mode.cpp`, code around vaddr `0x5feec`) calls `access("/tmp/config/hostapd.conf")`. If the file exists, it returns at once because the AP is already up.
2. Otherwise it calls `lp_get_best_wifi_channel()` (`0x75818`), which runs `ifconfig wlan0 up` and the two `iwlist` commands (see [`iwlist`](iwlist.md)). It then uses `sprintf` to build `%s ap nl80211 "%s" "%s" wpa %d` (wifi_setup.sh path, SSID, passphrase, channel) and runs the result through a `system()` wrapper (`0x7541c`, which logs `run commnd: `).
3. `wifi_setup.sh` writes `/tmp/config/hostapd.conf` with these lines:
   - `interface=wlan0`
   - `ctrl_interface=/var/run/hostapd`
   - `beacon_int=100`
   - `preamble=0`
   - `ssid=<ssid>`
   - `max_num_sta=5`
   - `channel=<ch>`
   - in WPA mode: `wpa=2`, `wpa_pairwise=CCMP`, `wpa_passphrase=<pwd>`, `wpa_key_mgmt=WPA-PSK`
4. The script then sets `wlan0` to `192.168.42.1`, runs `hostapd -B /tmp/config/hostapd.conf`, and starts [`udhcpd`](udhcpd.md).

The script sets `MODULE_ID=RTL8188FU`, but its chip-specific block tests `== "8188FU"`, so that block never runs. As a result, `hw_mode`, `driver`, `ieee80211n` and `wme_enabled` are never written. hostapd then falls back to its defaults: driver nl80211 (first in `wpa_drivers[]`) and, per upstream, `hw_mode=g` without 802.11n [INFERENCE].

`lp_app` checks whether a client has joined with `iw dev wlan0 station dump > /tmp/sta`, then `stat()`, then `st_size != 0` (see [`iw`](iw.md)). `lp_app` never talks to the hostapd control socket. `wifi_setup.sh stop` stops hostapd with `killall -9 hostapd`.

The `lp_app` strings next to `wifi_setup.sh` include `LPVC` and a plain-text string `Lang…[redacted]` (in `.rodata`, both builds). These look like the default AP SSID prefix and default AP passphrase [INFERENCE]. The configured values live in `/userdata/xhr_config.ini` `[wifi_ap]` (`ssid`, `pwd`).

Running it by hand, e.g. `wifi_setup.sh ap nl80211 <ssid> <pwd> wpa <ch>`, switches `wlan0` from station to AP mode and drops the camera's normal Wi-Fi link.

## Evidence

```
$ file hostapd ; sha256sum hostapd ; stat -c '%s' hostapd
ELF 32-bit LSB executable, ARM, EABI5 ... interpreter /lib/ld-uClibc.so.0, stripped
8be1f0410b88a02c0b76da37bdeb50dd41d22298b1c6a81adbdd30231e015a10  680436
$ readelf -d hostapd | grep NEEDED
libnl-3.so.200 libnl-genl-3.so.200 libnl-route-3.so.200 libc.so.0 ld-uClibc.so.1
$ strings -n 4 hostapd | sed -n '222,226p'
2.10
hostapd v%s
...
Copyright (c) 2002-2022, Jouni Malinen <j@w1.fi> and contributors
$ strings hostapd | grep -xE 'wps_state|eap_server|auth_server_addr|owe_groups|WPS_PBC'   -> (no output)
$ strings hostapd | grep -E '^SAE: '                                                     -> (no output)
wpa_drivers[] @0x98470 -> ['nl80211', 'hostap', NULL]   (pointer-table walk in Python)
$ llvm-nm-14 -D --undefined-only hostapd | grep rtnl_
rtnl_link_add rtnl_link_vlan_set_id rtnl_neigh_add rtnl_neigh_delete ...
$ grep -n hostapd downlaods/3/dump/oem/usr/sbin/wifi_setup.sh
HOSTAP_CTRL_INTERFACE=/var/run/hostapd
HOST_CONFIG=$DIR_CONFIG/hostapd.conf
	CMD="hostapd -B ${HOST_CONFIG}"
$ strings -n 4 lp_app | grep -E 'hostapd|ap nl80211'
/tmp/config/hostapd.conf
%s ap nl80211 "%s" "%s" wpa %d
lp_app 0x5ff00: bl access("/tmp/config/hostapd.conf"); beq -> return 1
lp_app 0x5ff88: bl sprintf ; 0x5ffd8: bl 0x7541c (system wrapper)
```

## Open questions

- Which configuration hostapd actually runs with on the device: whether the RTL8188FU (`8188fu.ko`, cfg80211-based, kernel 5.10.110) accepts nl80211 AP mode with the default `hw_mode=g` and no HT. Answering this needs the device in AP mode (`/tmp/config/hostapd.conf` is absent from the dump; `/run/wpa_supplicant` exists, so the dump was taken in station mode).
- That SAE/OWE/DPP are missing is [INFERENCE] from absent strings and the lack of an EC-capable crypto library. It has not been confirmed by disassembling the auth-algorithm switch.
- SSID and passphrase handling is unsafe: they go unescaped into a double-quoted `system()` command line in `lp_app` and are written with `echo` into `hostapd.conf`. Characters such as `"`, `` ` ``, `$` or a newline in the configured SSID or password could break the command or inject config lines [INFERENCE: not exercised].
- Resolved: `wpa_supplicant` (`/usr/bin/wpa_supplicant`, `wpa_supplicant v2.6`) and `wpa_cli` (`/usr/bin/wpa_cli`) exist on the camera; `hostapd_cli` does not exist, so its only mention (the `usages()` hint in `wifi_setup.sh`) cannot be followed (verified read-only on the live camera, 2026-10-31).
