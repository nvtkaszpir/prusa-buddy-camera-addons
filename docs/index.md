
# About

This repo contains some customizations to the official Prusa Buddy3D camera that
comes with the Prusa CORE One L.

## Disclaimer

!!! warning

    This project is not affiliated with, endorsed by, sponsored by or supported by Prusa Research a.s.,
    Prusa Development a.s. or any of their partners in any way. It is an independent community project.
    Do not contact Prusa support about problems caused by these add-ons.

    All you see in this repo was coded with Anthropic Claude Opus 5.5 or newer.

    This code comes without any warranty, use at your own risk. Installing it changes how the camera
    behaves and may void your warranty.

### Trademarks

Prusa, Prusa Research, Original Prusa, Prusa CORE One, Prusa Connect and Buddy3D are names and trademarks of
Prusa Development a.s. and Prusa Research a.s. JOSEF PRUSA, PRUSA RESEARCH, PRUSA 3D and PRUSAMENT are
registered trademarks of Prusa Development a.s., used by Prusa Research a.s. under licence. Buddy3D is a Prusa
Research brand, and Prusa Development a.s. has applied to register BUDDY3D as a trademark. Rockchip and all
other names are trademarks of their respective owners.

These names are used only to say which hardware and services this project works with. No logos are used, and
their use does not imply any endorsement.

### Copyright and license

The camera firmware is copyrighted by its respective owners and is not part of this project. File names,
paths, log lines and short excerpts of the firmware quoted in these pages are there only to document how the
camera works, for interoperability.

The project's own files, including this documentation, are released under the
[MIT License](https://github.com/nvtkaszpir/prusa-buddy-camera-addons/blob/master/LICENSE). The prebuilt
third-party binaries it installs keep their own licenses (GPL, LGPL, BSD, MIT, Apache-2.0, Zlib); the
[README](https://github.com/nvtkaszpir/prusa-buddy-camera-addons#license) lists each one.

## Known limitations

- tested only with Prusa Buddy3D camera that comes with the Prusa CORE One L,
  it may work with other models, not tested
- tested with firmware cam-3.1.3

## Sections

- [Install](install/index.md): requirements, minimal settings and installation steps.

- [Features](features/index.md)

- [Findings](findings/index.md): per-file analysis of `/oem/usr/bin` and `/oem/usr/sbin`,
  plus topic pages such as [Video](findings/video.md).
