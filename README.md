# Prusa Buddy3D camera add-ons

Add-ons for the Buddy3D camera that ships with the Prusa CORE One L:

- SSH access (dropbear),
- an HTTP file server for timelapse downloads (lighttpd),
- rsync,
- remote syslog (rsyslog),
- log rotation,
- time sync
- a microSD card check (fsck.fat)

Tested with camera firmware cam-3.1.3.

Documentation: <https://nvtkaszpir.github.io/prusa-buddy-camera-addons/> (built from [`docs/`](docs/)).

## Disclaimer

This project is not affiliated with, endorsed by, sponsored by or supported by Prusa Research a.s., Prusa
Development a.s. or any of their partners in any way. It is an independent community project. Do not contact
Prusa support about problems caused by these add-ons.

The code comes without any warranty; use it at your own risk. Installing it changes how the camera behaves and
may void your warranty. All code in this repository was written with Anthropic Claude Opus 5.5 or newer.

## Trademarks

Prusa, Prusa Research, Original Prusa, Prusa CORE One, Prusa Connect and Buddy3D are names and trademarks of
Prusa Development a.s. and Prusa Research a.s. JOSEF PRUSA, PRUSA RESEARCH, PRUSA 3D and PRUSAMENT are
registered trademarks of Prusa Development a.s., used by Prusa Research a.s. under licence. Buddy3D is a Prusa
Research brand, and Prusa Development a.s. has applied to register BUDDY3D as a trademark. Rockchip and all
other names are trademarks of their respective owners.

These names are used only to say which hardware and services this project works with. No logos are used, and
their use does not imply any endorsement.

## Copyright

The camera firmware is copyrighted by its respective owners and is not part of this repository. File names,
paths, log lines and short excerpts of the firmware quoted in the documentation are there only to document how
the camera works, for interoperability.

## License

The project's own files (scripts, configuration, `ntpsync.c`, Taskfile and documentation) are released under
the [MIT License](LICENSE).

The prebuilt binaries in [`buddy-addons/out/`](buddy-addons/out/) are third-party software and keep their own
licenses. Each is built from upstream release tarballs by the matching `buddy-addons/build-*.sh` script, which
names the exact source version, download URL and SHA-256 and can rebuild the binary. The only source change is
in `build-lighttpd.sh`, which edits lighttpd's `src/Makefile.am` to choose the statically linked modules. The
binaries are statically linked with musl libc (MIT), except `rsyslog/`, whose programs and modules are
dynamically linked against the bundled musl loader `ld-musl-armhf.so.1`.

- `dropbearmulti`: Dropbear 2026.94, MIT-style license (see its `LICENSE`).
- `lighttpd`: lighttpd 1.4.85 (BSD-3-Clause), with Mbed TLS 3.6.7 (Apache-2.0 OR GPL-2.0-or-later) and
  PCRE2 10.49 (BSD-3-Clause).
- `mbedtls-gen-key`, `mbedtls-cert-write`: Mbed TLS 3.6.7 (Apache-2.0 OR GPL-2.0-or-later).
- `rsync`: rsync 3.5.1 (GPL-3.0-or-later), with zlib 1.3.2 (Zlib).
- `rsyslog/`: rsyslog 8.2610.0 (GPL-3.0-or-later, LGPL-3.0-or-later and Apache-2.0; see its `COPYING*` files),
  libestr 0.1.11 (LGPL-2.1), libfastjson 1.2609.0 (MIT), zlib 1.3.2 (Zlib) and the musl dynamic loader (MIT).
- `logrotate`: logrotate 3.22.0 (GPL-2.0-or-later), with popt 1.19 (MIT).
- `fsck.fat`: dosfstools 4.2 (GPL-3.0-or-later).
- `drill`: ldns 1.9.2 (BSD-3-Clause).
- `ntpsync`: [`buddy-addons/ntpsync.c`](buddy-addons/ntpsync.c), part of this project (MIT).
