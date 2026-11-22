# Install

How to get the add-ons from this repo onto the camera.

1. [Requirements](1-requirements.md): camera, microSD card, network and host tools.
2. [Minimal settings](2-minimal-settings.md): the values you must set before the first boot.
3. [Installation](3-installation.md): build, copy to the microSD card, add the boot hook, boot and verify.
4. [Uninstall](uninstall.md): what the add-ons leave on the camera, and how to remove them over ssh or from the
   microSD card.
5. [Firmware update](firmware-update.md): put a chosen firmware package on the microSD card so the camera flashes
   it on the next boot, over ssh or with the card in a computer.

The microSD card is the source of truth. Binaries, configs and keys live in `/mnt/sdcard/bin/`, and the start
scripts copy them to `/userdata` on every boot, so a wiped `/userdata` is filled again on the next boot.

Each add-on is optional. Copy only the files of the [features](../features/index.md) you want, and paste only their
boot hook blocks.
