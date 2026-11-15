# drill (DNS lookups)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile), [Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/drill` | ldns 1.9.2, `build-drill.sh` | `drill`, NLnet Labs' dig-style DNS lookup tool, built without OpenSSL | 207292 B | `337933f197ba1e1e25b461af43df4e28ab7835b1f18b8c6e2a38c4e0c6b34ea7` |

```sh
./build-drill.sh                                  # -> out/drill
qemu-arm-static out/drill -v                      # drill version 1.9.2
```

## Install

On the card (optional):

```
/mnt/sdcard/bin/drill              <- out/drill (optional)
```

```sh
cp out/drill "$SD/bin/"
sync
```

`start-sshd.sh` (see [dropbear.md](dropbear.md#what-happens-at-boot)) copies it to `/userdata/bin/` at boot if it is present on the card and its md5 differs. Without the card, upload it as in [Upload via telnet](README.md#upload-via-telnet).

lighttpd's `start-httpd.sh` also installs `drill` from the card and uses `/userdata/bin/drill -x` to find the camera's DNS name for the listing title (see [lighttpd.md](lighttpd.md#listing-title)).

## Use

`drill` is the dig counterpart from NLnet Labs' ldns. The query syntax and output format follow dig, but the options use `-` flags instead of `+` ones (no `+short`). It reads `/etc/resolv.conf` (on the camera a link to `/tmp/resolv.conf`, written by the Wi-Fi DHCP client) unless you give `@server`. Login shells drop `/userdata/bin` from PATH, so use the full path:

```sh
/userdata/bin/drill prusa3d.com                  # A record via the DHCP resolvers
/userdata/bin/drill @1.1.1.1 prusa3d.com MX      # specific server and type
/userdata/bin/drill -t @1.1.1.1 prusa3d.com      # TCP instead of UDP
/userdata/bin/drill -x 192.168.1.5               # reverse (PTR) lookup
/userdata/bin/drill -T prusa3d.com               # trace from the root servers, like dig +trace
```

Without OpenSSL nothing is validated: `-D` sets the DO bit and shows RRSIG/DNSKEY records, but signature chasing (`-S`) is not compiled in. Over ssh, `ssh camera /userdata/bin/drill ...` works too.

## Verified

On the host (qemu-user): A, MX over TCP, PTR, `-D` DNSSEC records, and `-T` trace against live resolvers.

On the camera (run from `/tmp`, then removed): A lookup via the DHCP resolvers in `/etc/resolv.conf`, MX over TCP to `@1.1.1.1`, and a PTR lookup, all `NOERROR`, with md5 matching the build.

Installed from the card by `start-sshd.sh` (log: `installed drill (md5 a8608f2079ec032e551204eed38ffbc4)`). `drill -x 192.168.1.75` returned `buddy-cam-1.intra.hlds.pl`. 