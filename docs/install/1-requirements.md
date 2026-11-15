# Requirements

## Host

A Linux host with:

| tool | needed for |
|---|---|
| `docker`, usable by your user | building the ARM binaries (`dockcross/linux-armv7l-musl` image) |
| `curl`, `sha256sum`, `bash` | build scripts: downloading and checking source tarballs |
| `task` ([go-task](https://taskfile.dev/)) | `task buddy:stage` (sets the syslog target) and `task buddy:sync` |
| `rsync` | copying the staged files to the card or to the camera |
| `ssh`, `scp` (OpenSSH) and an ssh key pair | logging in to the camera, `install-cert.sh`, `task buddy:sync` |
| `openssl` 1.1.1 or newer | `gen-htpasswd.sh` (HTTPS feature) and `gen-cert.sh` (optional own certificate) |
| `curl` or `wget` | downloading files from the HTTPS feature |

No ARM toolchain needs to be installed; the build scripts run inside the docker image.

## Camera

- Prusa Buddy3D camera that comes with the Core One L. Other models are not tested.
- Firmware cam-3.1.3. Other versions are not tested.
- The camera already set up and connected to your Wi-Fi network (station mode), and its IP address known.
  The examples use `CAMERA_IP`; `Taskfile.yml` calls it `CAMERA_HOST`.
- Hardware facts that limit what runs on it: ARMv7l Cortex-A7, about 34 MB RAM with only about 6–7 MB free while
  `lp_app` runs, busybox 1.27.2 + uClibc userland. The add-ons are static musl binaries (rsyslog ships its own musl
  loader), so they need nothing from the device's libc.

!!! warning "Trusted network only"
    The stock camera serves RTSP video without a password, and basic auth over plain HTTP sends the password
    readable on the network. Keep the camera on a trusted or isolated network.

## microSD card

- A microSD card in the camera, formatted vfat (FAT32). The camera mounts it at `/mnt/sdcard` from
  `/dev/mmcblk1p1`.
- A card reader on the host for the first install. Later updates can go over ssh.
- Free space for the binaries (a few MB) and for logs and timelapse files.


## Optional

- A syslog server reachable from the camera (UDP or TCP 514), only for the [remote rsyslog](../features/rsyslog.md)
  feature.
- `uvx` ([uv](https://docs.astral.sh/uv/)), only to build or serve these docs (`task docs:build`, `task docs:serve`).
