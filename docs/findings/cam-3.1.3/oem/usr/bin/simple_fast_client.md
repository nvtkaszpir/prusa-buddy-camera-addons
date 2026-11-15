# `simple_fast_client`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/simple_fast_client` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `1142260` |
| sha256 | `bf5bb33b3cfbfbf2800f71fcf17bebbd8e4d6eac81653ad658a66f715c6f7741` |
| linked libraries | `librkaiq.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0, ld-uClibc.so.1` |
| origin | Rockchip RV1106 SDK rockit sample for the fast-boot ("thunderboot") flow, a `simple_*` sample. It statically links rockit (same git version as `/oem/usr/lib/librockit.so`), MPP, librga and the `rtsp_demo` library. [INFERENCE] the exact SDK source path. |
| confidence | medium-high (the pipeline and AIQ fast-boot sequence come straight from the disassembly; "fast" = fast boot is inferred from the cmdline/IQ-preload logic) |

## Summary

`simple_fast_client` is a Rockchip demo client for the **fast-boot** camera path. It does not talk to a separate daemon. "Client" means it attaches, in user space, to a VI→VENC channel 0 that it never creates itself; on a fast-boot build that channel is already running from early boot. It also brings up ISP 3A (rkaiq) from an IQ binary and a day/night flag that the bootloader pre-loaded into RAM (addresses passed on `/proc/cmdline`). Two extra encoders are added: VENC1 H.264 1280x720 and VENC2 MJPEG 640x360. VENC channel 0 is streamed over RTSP at `rtsp://<cam>:554/live/0`. It is a leftover SDK demo: nothing on this camera starts it, and the camera does not use a fast-boot kernel (`rockit.ko` is loaded as a module by `insmod_ko.sh`).

The `dumpsys`-like strings inside it are not a separate tool. They are the rockit dump **server** (`RKSockServer` on `tcp://127.0.0.1:3893`), linked statically into this binary. Here it is started by `RK_MPI_SYS_Init` and torn down by `RK_MPI_SYS_Exit`. `/oem/usr/bin/dumpsys` is the matching client (see `dumpsys.md`). Programs that link `librockit.so` dynamically get the same server only while they are between a successful `RK_MPI_SYS_Init` and `RK_MPI_SYS_Exit`. On the live camera the production app `lp_app` shows **no** 127.0.0.1:3893 listener (see "Relevance on this camera" and `dumpsys.md`).

## Usage

No command-line options. The program imports neither `getopt` nor `getopt_long`, `main` never reads `argv`, and there is no usage or help string of its own. It runs until it gets SIGINT (Ctrl-C) or until a stream thread passes the loop limit (global = 1000000 frames).

The help-like strings found in the binary belong to the embedded rockit dump server, which serves requests from `/oem/usr/bin/dumpsys`, not from this program's command line:

```
./dumpsys record [-m MOD] [-d DEVID] [-c CHNID] [-o OUTPUT FILE]...
args not enough when record in. eg: dumpsys tde record_begin /tmp/ 10
```

## How it works

Reconstructed from `main` (0x180e4), which is found via `_start`'s literal passed to `__uClibc_main`. Calls to the statically linked RK_MPI API go through a block of one-instruction thunks at 0x1889c–0x18a88. These were mapped to names by matching their order and shapes against the identical export layout of `librockit.so` (e.g. `RK_MPI_SYS_Init/Exit/Bind/UnBind` = 0x188a0/a4/a8/ac, the same order as `librockit.so` 0x541a8…). [INFERENCE] where noted.

1. `log("main")`. Every `log()` call (sub_18088) appends `[app-cli]: %s` to `/dev/kmsg`, so the boot-timing marks land in the kernel log.
2. `signal(SIGINT, handler)`. The handler sets `g_quit = 1`.
3. `RK_MPI_SYS_Init()`, or `rockit init fail`. Inside it, rockit also starts the `ipcs_server` dump server on `tcp://127.0.0.1:3893` (SYS_Init 0x18af0 → 0x3eebc → 0x3ed30, which references both strings). Then `log("SYS_Init")`.
4. `fopen("/tmp/venc-test.bin", "w")`.
5. VENC channel 1 (sub_17ac4(1, 1280, 720, 8)):
   - codec id 8 = H.264, profile 100 (High), stream buffer count 5, buffer size w*h/2.
   - RC mode 1 (H264CBR), bitrate 2048, gop 60.
   - Calls: `RK_MPI_VENC_CreateChn`, then `SetChnBufWrapAttr({0,1080})` and `SetChnRefBufShareAttr({1})` [INFERENCE: names by thunk order], then `StartRecvFrame(-1)`. Logs `venc chn1`.
6. VENC channel 2 (sub_179cc(2, 640, 360, 9)): codec 9 = MJPEG, RC mode 5 [INFERENCE: MJPEGVBR], `CreateChn`, a setter called with 75 [INFERENCE: `SetJpegParam` Qfactor 75], `StartRecvFrame(-1)`. Logs `venc chn2`.
7. VI channels 1 (1280x720) and 2 (640x360) on pipe 0 (sub_17d74): `RK_MPI_VI_SetChnAttr` then `RK_MPI_VI_EnableChn`. Prints `  vi en: %lld us` or `ERROR: create VI  %d, error! ret=%d`. The program never configures the VI device: the helper that would call `VI_GetDevAttr/SetDevAttr/EnableDev/SetDevBindPipe` (sub_17c60) has no callers.
8. `RK_MPI_SYS_Bind({VI(8),0,1} → {VENC(4),0,1})` and `({VI,0,2} → {VENC,0,2})`. Logs `bind chn 1` / `bind chn 2`. The module IDs match rockit's ID→name table (`cmpi mb sys rgn venc vdec vpss vgs vi …`).
9. Three `pthread_create`:
   - Thread 0x17758, arg 1 and arg 2 (one per extra encoder): loops `RK_MPI_VENC_GetStream(chn, 1000ms)` / `ReleaseStream`. Prints `chn:%d, loopCount:%d enc->seq:%d,pts=%lld` for the first 30 packets. The streams are discarded.
   - Thread 0x1789c, arg 2: loops `RK_MPI_VI_GetChnFrame(pipe 0, chn 2)` / `ReleaseChnFrame`. Prints `piple: %d, chn:%d, loopCount:%d vi->seq:%d pts=%lld`.
10. ISP 3A fast start. All values are parsed from `/proc/cmdline` by sub_17f9c (`strstr("<key>=")` + `strtol`, printing `get %s value: 0x%0lx`):
   - `rk_cam_hdr`: if `== 5`, the working mode is 0x10 (HDR2) and it logs `aiq in hdr mode`; otherwise mode 0 (normal).
   - `bw_night_addr` (hex): `open("/dev/mem", O_RDWR|O_DSYNC)`, `mmap` one page at that physical address, and read a 32-bit night flag.
   - `rk_iqbin_addr` / `rk_iqbin_size` (hex): `mmap` the IQ binary that was pre-loaded in RAM.
   - `rk_aiq_uapi2_sysctl_enumStaticMetas(0, &meta)` returns the sensor entity name.
   - `rk_aiq_uapi2_sysctl_preInit_scene(sns, "normal", "night"|"day")`, printing `=====night mode=====` or `=====day mode=======`.
   - `rk_aiq_uapi2_sysctl_preInit_iq_addr(sns, iq_ptr, iq_size)`. On failure it prints `%s: failed to load binary iqfiles` and continues.
   - `rk_aiq_uapi2_sysctl_init(sns, "/etc/iqfiles/", NULL, NULL)` → `rk_aiq_uapi2_sysctl_prepare(ctx, 0, 0, mode)` → `rk_aiq_uapi2_sysctl_start(ctx)`. Logs `aiq start` and prints `Aiq:%lld us` (time since step 9).
11. The main thread then runs the channel-0 loop (sub_172a8) until `g_quit`:
   - `RK_MPI_VENC_GetStream(0, 1000ms)`. VENC chn 0 is never created by this program.
   - The first ≤31 packets are written to `/tmp/venc-test.bin`, via `RK_MPI_MB_Handle2VirAddr` [INFERENCE] + `fwrite`.
   - For the first 30 packets it prints `chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus` and writes `seq:%u, pts:%llums` to `/tmp/pts.txt`.
   - After 30 packets it creates the RTSP server with `rtsp_new_demo(554)` (embedded `rtsp_demo.c`: `rtsp server demo starting on port %d`) and a session `rtsp_new_session(demo, "/live/0")`. It calls `RK_MPI_VENC_GetChnAttr(0)` and runs `rtsp_set_video(codec 1)` if the type is 8 (H.264) or codec 2 if the type is 12 (H.265). After that every packet goes out through `rtsp_tx_video` and `rtsp_do_event`.
   - On GetStream errors it prints `RK_MPI_VENC_GetChnFrame fail %x` (first 10 times).
12. Teardown:
   - `pthread_join` ×3, `SYS_UnBind` ×2, `VI_DisableChn` ×2, `VENC_StopRecvFrame` ×2, `VENC_DestroyChn` ×2, `VI_DisableDev`.
   - RTSP teardown, `close`/`munmap` of `/dev/mem`, `rk_aiq_uapi2_sysctl_stop`/`deinit`, `RK_MPI_SYS_Exit`.

Why "fast client":

- VENC chn 0 and VI chn 0 are consumed but never created.
- The VI device is never configured.
- The ISP IQ data and day/night state come from bootloader-provided physical addresses on the kernel command line.
- AIQ is started *after* the encoders are already running.
- Timing marks go to `/dev/kmsg`.

All of this matches Rockchip's RV1106 fast-boot design, where the kernel/rockit starts sensor→ISP→VENC0 before user space, and the user-space "client" later takes over 3A and output. The embedded rockit has matching code (`venc_init_persist_chn`, `venc_init_persist_chn2`). [INFERENCE] for the fast-boot interpretation.

Statically linked components (that is why the binary is 1.1 MB):

- rockit: same git tag as `librockit.so` (`git-169ca8392 Sat Nov 5 16:04:08 2022 +0800`), with the RTMediaBuffer/RTAllocator classes and the audio codecs.
- MPP: `8cae7ec7 author: toby.zhang 2022-09-29 [Vepu540c]...`.
- librga (`rga_im2d`).
- `rtsp_demo.c`.

Only `librkaiq.so` is linked dynamically.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/dev/mem` (RW mmap of bootloader-provided physical addresses).
  - `/dev/kmsg` (write).
  - `/proc/cmdline` (read).
  - Through the embedded rockit/MPP/RGA: `/dev/mpi/valloc`, `/dev/mpi/vsys`, `/dev/mpi/vrgn`, `/dev/mpi/venc`, `/dev/mpi/vpss`, `/dev/mpi/vvi`, `/dev/mpi/vrga`, `/dev/rga`, `/dev/vcodec`, `/dev/ion`, `/dev/video*`, `/dev/media%d`, `/dev/snd/pcmC%uD%u%c`, `/sys/dev/char/%u:%u`, `/proc/device-tree/compatible`, `/proc/cpuinfo`, `/sys/bus/nvmem/devices/rockchip-efuse0/nvmem`. These are library code paths; the ones this program actually drives are the VI/VENC/SYS/MB ones.
- Files and paths read/written:
  - Writes `/tmp/venc-test.bin` (first ≤31 H.264/H.265 packets of VENC chn 0) and `/tmp/pts.txt`.
  - Reads `/etc/iqfiles/` (AIQ fallback IQ directory; on this dump it holds `CAC_sc4336_OT01_40IRC_F16`, `CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16`, `jx_f37p_AXF37AA_SR2012A.json`).
- Network:
  - RTSP server on TCP port 554, path `/live/0` (`rtsp://<camera-ip>/live/0`), RTP over UDP or interleaved.
  - rockit dump server on TCP `127.0.0.1:3893`, loopback only, URI `/rockit/mpi/dump`.
- Environment variables / config files:
  - Kernel command-line keys `rk_cam_hdr`, `bw_night_addr`, `rk_iqbin_addr`, `rk_iqbin_size`.
  - rockit's usual `rt_*` debug/log properties (e.g. `rt_log_level`) through the embedded library. [INFERENCE: not traced]

## Relevance on this camera

- Not started at boot and not referenced anywhere. `grep -r simple_fast_client downlaods/3/dump/` matches only the binary itself. `RkLunch.sh` / `S21appinit` start `lp_app`, not this.
- The camera does not run the fast-boot flow this demo expects: `/oem/usr/ko/insmod_ko.sh` loads `rockit.ko` as a normal module, and nothing in the dump references `rk_iqbin_addr` / `bw_night_addr` / `rk_cam_hdr` except this binary. If started by hand, VENC chn 0 will probably not exist, so the main loop only prints `RK_MPI_VENC_GetChnFrame fail` and RTSP never starts.
  - The missing cmdline keys parse as 0, so the program `mmap`s physical page 0 through `/dev/mem` and reads it as the night flag. `rk_iqbin_size = 0` makes the IQ mmap and `preInit_iq_addr` fail ("failed to load binary iqfiles"), and AIQ then falls back to `/etc/iqfiles/`. [INFERENCE]
- Conflicts if run while `lp_app` is running: `lp_app` also uses rockit (`librockit.so`) and owns the ISP/VI/VENC channels (its log shows `RK_MPI_VENC_StartRecvFrame success for stream 0`).
  - Creating VENC 1/2 or VI 1/2, binding, `VI_DisableDev` on exit, and a second `rk_aiq` instance on the same sensor would interfere with or break `lp_app`'s pipeline.
  - On exit it also tears down channels 1 and 2, which may be `lp_app`'s.
  - Port 554 is already taken by `lp_app` (live `netstat -ln` shows `tcp 0.0.0.0:554 LISTEN`; `lp_app.sh` forces `rtsp_server_mode=2`), so `rtsp_new_demo(554)` would fail to bind. 127.0.0.1:3893 is **not** in use on the live camera: the same `netstat -ln` shows no listener there while `lp_app` runs. The reason is unknown; see `dumpsys.md`. [INFERENCE] So this program's own embedded dump server would probably bind 3893 successfully. `dumpsys` would then talk to `simple_fast_client`'s rockit instance, not to `lp_app`'s.
- Side effects: no flash writes, GPIO, PWM or reboot. It writes to `/tmp` and `/dev/kmsg`, maps `/dev/mem` read/write (it only reads), and starts the ISP 3A engine.

## Evidence

- `readelf -d`: NEEDED `librkaiq.so libstdc++.so.6 libgcc_s.so.1 libc.so.0 ld-uClibc.so.1`.
- `llvm-nm-14 -D --undefined-only`:
  - The only vendor imports are `rk_aiq_uapi2_sysctl_{enumStaticMetas,preInit_scene,preInit_iq_addr,init,prepare,start,stop,deinit}`.
  - libc includes `socket bind listen accept sendto recvfrom mmap64 open64 ioctl dlopen pthread_*`.
  - No `RK_MPI_*` imports (statically linked) and no getopt.
- App strings (`strings -n 4`, contiguous block):
  ```
  /tmp/pts.txt
  chn:0, loopCount:%d enc->seq:%d wd:%d pts=%lld delay=%lldus
  rtsp create fail / /live/0 / rtsp create session fail
  RK_MPI_VENC_GetChnAttr fail %x / RK_MPI_VENC_GetChnFrame fail %x
  /proc/cmdline / /dev/kmsg / [app-cli]: %s / /tmp/venc-test.bin
  rockit init fail / SYS_Init / venc chn1 / venc chn2 / vi ch1 / vi chn2 / bind chn 1 / bind chn 2
  rk_cam_hdr / bw_night_addr / /dev/mem / rk_iqbin_addr / rk_iqbin_size
  =====night mode===== / night / normal / =====day mode======= / /etc/iqfiles/ / aiq in hdr mode / Aiq:%lld us
  ```
- `main` disassembly excerpt (annotated):
  ```
  181f8 bl sub_17ac4(1,1280,720,8)        ; "venc chn1"  H.264
  18218 bl sub_179cc(2,640,360,9)         ; "venc chn2"  MJPEG
  18234 bl sub_17d74(1,1280,720)          ; "vi ch1"
  182a0 bl 0x188a8 (SYS_Bind {8,0,1}->{4,0,1})
  18314/2c/44 pthread_create(0x17758,1) (0x1789c,2) (0x17758,2)
  1836c sub_17f9c("rk_cam_hdr",0) ; ==5 -> mode 0x10
  183bc open64("/dev/mem",0x1002) ; 18418 mmap64(4096 @ bw_night_addr&~0xfff)
  184ac mmap64(rk_iqbin_size @ rk_iqbin_addr)
  184dc rk_aiq_uapi2_sysctl_enumStaticMetas ; 18510/64 preInit_scene ; 185a4 preInit_iq_addr
  185e0 rk_aiq_uapi2_sysctl_init(sns,"/etc/iqfiles/",0,0) ; 18638 prepare ; 18660 start
  186d0 bl sub_172a8(0)  ; chn-0 loop: GetStream(0) -> fwrite / rtsp_new_demo(554) / "/live/0"
  ```
- Embedded dump server: strings `tcp://127.0.0.1:3893` (xref 0x3ed64), `ipcs_server` (0x3edb0), `/rockit/mpi/dump`, `RKSockServer`, and `client connected. waiting for msg...`. The path is `RK_MPI_SYS_Init` (0x18af0) `bl 0x3eebc` → `b 0x3ed30`. The module-name table at `.data.rel.ro` 0x1255cc is `cmpi mb sys rgn venc vdec vpss vgs vi vo ai ao aenc adec tde isp wbc avs rga af ivs`.
- Version strings identical to `librockit.so`: `git-169ca8392 Sat Nov 5 16:04:08 2022 +0800`, `rockit version: %s`, `rockit-ko version: %s`.
- Live device, `netstat -ln` while `lp_app` (pid 357, `lp_app --noshell --log2file /mnt/sdcard/logs`) runs:
  ```
  tcp  0.0.0.0:554  LISTEN      (RTSP)
  tcp  0.0.0.0:22   LISTEN      (dropbear, added by user)
  tcp  0.0.0.0:23   LISTEN      (busybox telnetd)
  unix STREAM  LISTENING /tmp/UNIX.domain
  unix SEQPACKET LISTENING /run/udev/control
  ```
  There is no 127.0.0.1:3893 listener. In the dumped `librockit.so` the server is started inside `RK_MPI_SYS_Init` with no env/config guard, and the dumped `lp_app` calls `RK_MPI_SYS_Init` in its `init`. The condition that suppresses the listener live is therefore unknown (analysis and candidate explanations in `dumpsys.md`). `/tmp/UNIX.domain` comes from `librkaiq.so` (string at 0xf3362), not from rockit.

## Open questions

- Whether this camera's bootloader or kernel ever passes `rk_iqbin_addr` / `bw_night_addr` / `rk_cam_hdr`. Reading `/proc/cmdline` on the device would settle it. The `rockit.ko` module load in `insmod_ko.sh` suggests a normal, non-fast-boot build. [INFERENCE]
- Several RK_MPI thunks were named only by their order against `librockit.so`'s export layout: `SetChnBufWrapAttr`, `SetChnRefBufShareAttr`, `SetJpegParam`, `MB_Handle2VirAddr`, the VI device calls, and the RC-mode enum values (1 = H264CBR, 5 = MJPEGVBR). [INFERENCE]
- Which entity VI chn 1/2 use: the `aEntityName` global is never set, so rockit's default applies, and that default was not resolved.
- The exact Rockchip SDK source this was built from (the name suggests `simple_fast_client.c` in the RV1106 media samples). [INFERENCE]
