# `iwlist`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/iwlist` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `62884` |
| sha256 | `c066f96380f11cec94ce4b2592b9b2bcd52021a397fb1b9902888b80fab70bd7` |
| linked libraries | `libc.so.0, ld-uClibc.so.1` |
| origin | upstream Linux Wireless Tools (Jean Tourrilhes), version 30 (`WT_VERSION` 30, WE v11–v22): the `iwmulticall` multi-call binary installed under the name `iwlist`, with `libiw` linked statically |
| confidence | high |

## Summary

This is the Wireless Tools `iwmulticall` binary. It contains `iwconfig`, `iwlist`, `iwspy`, `iwpriv` and `iwgetid` and picks the tool from the name it was called by. Installed as `iwlist`, it queries Wireless Extensions (WEXT) information such as scan results and supported channels. `lp_app` uses it to pick the least-crowded 2.4 GHz channel before it starts the setup access point. The binary is md5-identical on the running camera.

## Usage

The `iwlist` usage is built at runtime from `Usage: iwlist` and `%s [interface] %s %s`. The verified command table (vaddr `0x1add4`, 16-byte `{name, fn, max_args, argsyntax}` records) is:

```
Usage: iwlist [interface] scanning [essid NNN] [last]
              [interface] frequency
              [interface] channel
              [interface] bitrate
              [interface] rate
              [interface] encryption
              [interface] keys
              [interface] power
              [interface] txpower
              [interface] retry
              [interface] ap
              [interface] accesspoints
              [interface] peers
              [interface] event
              [interface] auth
              [interface] wpakeys
              [interface] genie
              [interface] modulation
```

Built from the table above; each line follows the binary's format strings. The other tools in the binary have these usages, verbatim:

```
Usage: iwconfig [interface]
                interface %s %s
       Check man pages for more details.
Usage: iwspy interface [+] [MAC address] [IP address]
Usage: iwpriv interface [private-command [private-arguments]]
Usage iwgetid [OPTIONS] [ifname]
  Options are:
    -a,--ap       Print the access point address
    -c,--channel  Print the current channel
    -f,--freq     Print the current frequency
    -m,--mode     Print the current mode
    -p,--protocol Print the protocol name
    -r,--raw      Format the output as raw value for shell scripts
    -s,--scheme   Format the output as a PCMCIA scheme identifier
    -h,--help     Print this message
```

The `iwlist` subcommands:

- `scanning`: trigger a scan (SIOCSIWSCAN) and print cells (SIOCGIWSCAN). Output looks like `Cell %02d - Address:`, `ESSID:"%s"`, `Frequency`/`Channel`, `Encryption key:`, `IE: WPA Version`/`IEEE 802.11i/WPA2 Version`.
- `frequency`/`channel`: list the supported channels and frequencies (`%d channels in total; available frequencies :`).
- `bitrate`/`rate`, `encryption`/`keys`, `power`, `txpower`, `retry`: driver capability and settings.
- `ap`/`accesspoints`/`peers`, `event`, `auth`, `wpakeys`, `genie`, `modulation`: further WEXT queries.
- `--version` prints `%-8.16s  Wireless-Tools version %d` with `30`, then `Compatible with Wireless Extension v11 to v%d.` with `22`, then the kernel's WE version.

## How it works

- **Dispatch.** `main` looks at the basename of `argv[0]` (`__xpg_basename` is imported) and compares it with `iwconfig`, `iwlist`, `iwspy`, `iwpriv` and `iwgetid`. If called as `iwmulticall`, it shifts `argv` once and checks again. Any other name prints `iwmulticall : you are not supposed to call me this way...`. There are no `iwevent` or `ifrename` strings, so those tools are not included. In the dump only the `iwlist` name exists, so the other tools would need a symlink or a renamed copy.
- **Back end.** Everything goes through `socket()` and `ioctl()` with Wireless Extensions requests: `SIOCGIWSCAN`, `SIOCGIWENCODE`, `SIOCGIWENCODEEXT`, `SIOCGIWSPY`, `SIOCSIWTHRSPY` and the private ioctls. The interface list comes from `/proc/net/wireless`; if that fails it prints `Cannot read /proc/net/wireless`. There is no netlink and no libnl.
- **Version check.** The version routine at `0x12698` prints `Wireless-Tools version` with the immediate `mov r2, #30`, then `Wireless Extension v11 to v%d` with `mov r1, #22`. It then compares the kernel's WE version (`cmp r0, #15`) to decide which compatibility warning to print.
- **Other functions.** `gethostbyname`/`getnetbyname` are used by `iwspy`/`iwconfig` address parsing. `log10`/`pow`/`floor`/`ceil` handle dBm↔mW and frequency↔channel conversions (libm calls through uClibc).
- **Driver side.** The Realtek `8188fu.ko` has native WEXT handlers (`rtw_wx_set_scan`, `rtw_wx_set_enc`, `rtw_wx_set_pmkid` strings), so `iwlist wlan0 scan` and `iwlist wlan0 channel` work with this driver.

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/net/wireless`; WEXT ioctls on an `AF_INET` datagram socket bound to `wlan0`.
- Files and paths read/written: none of its own. When `lp_app` calls it, the shell redirects output to `/tmp/wifi_sup_channels` and `/tmp/wifi_env_channel`.
- Network: `scanning` makes the radio send 802.11 probe requests (active scan). No IP traffic.
- Environment variables / config files: none found.

## Relevance on this camera

`iwlist` is not started at boot, and no init script, [`RkLunch.sh`](../bin/RkLunch.sh.md) or [`wifi_setup.sh`](wifi_setup.sh.md) references it. Its only caller is [`lp_app`](lp_app.md), in `lp_get_best_wifi_channel()` (vaddr `0x75818`, `xhr_tools/Util/lp_system_tool.cpp` / `util.cpp` area). Each command goes through the logging `system()` wrapper `0x7541c`:

```
ifconfig wlan0 up
iwlist wlan0 channel | grep " Channel" > /tmp/wifi_sup_channels
iwlist wlan0 scan | grep Channel > /tmp/wifi_env_channel
```

After each command, `lp_app` builds the output file path from a sub-range of the command string. It reads the file line by line through a `std::function` callback (two lambdas `lp_get_best_wifi_channel()::{lambda(int)#1,#2}`, matching `Channel `) into a `std::map<int,int>` (`_Rb_tree<int, pair<const int,int>>`). It then walks the map to pick a channel.

The [INFERENCE] reading of this is: the first map holds the supported channels, the second counts neighbouring APs per channel, and the channel with the fewest APs wins. The AP-mode code logs that channel as `wifi_ap_mode best_channel: ` and passes it as the last argument of `wifi_setup.sh ap nl80211 "<ssid>" "<pwd>" wpa <channel>` (see [`hostapd`](hostapd.md)). This happens only when `/tmp/config/hostapd.conf` does not exist yet.

Running it by hand is read-only, apart from the radio activity of `scan`. A scan in station mode can briefly disturb an active connection.

## Evidence

```
$ file iwlist ; sha256sum iwlist ; stat -c %s iwlist
ELF 32-bit LSB executable, ARM ... stripped
c066f96380f11cec94ce4b2592b9b2bcd52021a397fb1b9902888b80fab70bd7  62884
$ readelf -d iwlist | grep NEEDED
libc.so.0 ld-uClibc.so.1
$ strings -n 3 iwlist | grep -nE 'iwmulticall|^iw(config|spy|priv|getid)$|Wireless-Tools'
159:%-8.16s  Wireless-Tools version %d
437:iwconfig  451:iwspy  461:iwpriv  464:iwmulticall  465:iwgetid
466:iwmulticall : you are not supposed to call me this way...
$ llvm-objdump -d --triple=armv7-linux-gnueabihf --start-address=0x12698 --stop-address=0x12730 iwlist
126c4: ldr r0,[pc,#84]  ; ->0x1be9c "Wireless-Tools version %d"
126c8: mov r2, #30
126d4: ldr r0,[pc,#72]  ; "Compatible with Wireless Extension v11 to v%d."
126d8: mov r1, #22
(Python) command table @0x1add4: scanning(-1,"[essid NNN] [last]"), frequency, channel, bitrate, rate,
  encryption, keys, power, txpower, retry, ap, accesspoints, peers, event, auth, wpakeys, genie, modulation
$ strings -n 4 lp_app | grep iwlist
iwlist wlan0 channel | grep " Channel" > /tmp/wifi_sup_channels
iwlist wlan0 scan | grep Channel > /tmp/wifi_env_channel
lp_app 0x75820..0x758bc: system-wrapper("ifconfig wlan0 up"), ("iwlist ... channel ..."), ("iwlist ... scan ...")
$ strings -n 4 oem/usr/ko/8188fu.ko | grep rtw_wx_set_scan
RTW: rtw_wx_set_scan, req->scan_type == IW_SCAN_TYPE_PASSIVE
```

## Open questions

- The exact upstream sub-release (e.g. `30.pre9`) cannot be read from the binary, which only stores the integer `WT_VERSION` 30.
- Exactly how `lp_app` picks the best channel (fewest APs, lowest summed RSSI, restricted to 1/6/11, etc.) has not been fully disassembled [INFERENCE].
- `iwlist wlan0 scan` while `wlan0` is in AP mode: if `/tmp/config/hostapd.conf` was removed while hostapd is running, the scan may fail or return nothing with the RTL8188FU driver [INFERENCE].
