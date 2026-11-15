# `mpi_enc_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/mpi_enc_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `84176` |
| sha256 | `2ea584e62a7d277d6dd6161e5aac8b8d9d1b7d8a84dce37b235445b774f3387e` |
| linked libraries | `librockchip_mpp.so.1, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip MPP test program (`test/mpi_enc_test.c` + `utils/mpi_enc_utils.c`, `utils.c`, `camera_source.c`, `iniparser`), RV1106 "mpp_interface" (kernel `mpp_vcodec`) variant with vendor additions (JPEG combo snapshot, `/dev/mpi/valloc`, `-c`/`-u`/`-v`/`-x` options) |
| confidence | high |

## Summary

Rockchip MPP command-line encoder test. It reads raw frames from a YUV/RGB file or a V4L2 capture node (`/dev/video*`), or generates a test pattern, encodes them with the hardware encoder (H.264, H.265 or MJPEG) through `librockchip_mpp` and the `mpp_vcodec` kernel driver, and writes the bitstream to a file. It is an SDK developer tool. The production app does not use it.

## Usage

`mpi_enc_test_help()` prints this usage text. `_show_options` formats it from an option table in `.data` (`-%s  %-16s\t%s\n`), then calls `mpp_show_support_format()` and `mpp_show_color_format()`. The table below was rebuilt from that option table (pointers at `.data` 0x341cc):

```
usage: mpi_enc_test [options]
-i  input_file        input bitstream file
-o  output_file       output bitstream file, 
-w  width             the width of input picture
-h  height            the height of input picture
-f  format            the format of input picture
-t  type              output stream coding type
-n  max frame number  max encoding frame number
-g  gop_mode          gop reference mode
-d  debug             debug flag
-b  bps target:min:max set tareget bps
-r  in/output fps     set input and output frame rate
-l  loop count        loop encoding times for each frame
```

(The `.data` table holds `{name, argname, help}` string triples. The argument format for `-g` (`gop_mode:gop_len:vi_len`) appears only in the parser's error message.)

The parser `mpi_enc_test_cmd_update_by_args` (0x16238) takes `-X value` pairs and dispatches on the option letter with a jump table for `b`..`x`. The disassembly shows these cases:

| opt | effect (from disassembly / error strings) |
|---|---|
| `-i <file>` | input file. Its name is passed to `name_to_frame_format()`, which guesses the format from names such as `yuv420sp`, `nv12`, `rgb888`, `fbc`. A name starting with `/dev/video` selects V4L2 camera input |
| `-o <file>` | output file. Its name is passed to `name_to_coding_type()` (`h264`/`264`/`avc`, `h265`/`265`/`hevc`, `jpg`/`mjpeg`) |
| `-w <n>` / `-h <n>` | width / height (`-help` prints the help instead) |
| `-u <n>` / `-v <n>` | horizontal / vertical stride (vendor letters; errors reuse "invalid input width" / "input height is invalid") |
| `-f <fmt>` | input pixel format: a number, or hex if it contains `x` (`0x%x`) |
| `-t <type>` | coding type as an `MppCodingType` number. It is checked with `mpp_check_support_format(MPP_CTX_ENC, type)` |
| `-n <num>` | max frames. MJPEG defaults to 1 frame ("jpege default encode only one frame. Use -n [num] for rc case") |
| `-g a:b:c` | `gop_mode:gop_len:vi_len` |
| `-b a:b:c:d` | `bps_target:bps_min:bps_max:rc_mode`, with "rc_mode 0:vbr 1:cbr 2:avbr 3:cvbr 4:fixqp" |
| `-r ...` | fps, either `num:den:flex` or `num:den:flex/num:den:flex` (separate input/output) |
| `-l <n>` | loop count (each frame is encoded n times) |
| `-c <n>` | JPEG channel id (`input chan_id is invalid`). It is passed to `mpp_frame_set_jpege_chan_id` |
| `-x <file>` | the file is loaded with `iniparser_load()` and the result is stored in the cmd struct. No `iniparser_get*` call exists outside the iniparser module, so the loaded values appear unused |
| `-d` | listed in help, but the jump-table entry for `d` goes to the default case "skip invalid opt %c" |

Behaviour is also controlled by MPP environment variables read with `mpp_env_get_u32` (see Interfaces).

## How it works

- `main` (0x12fb0): `mpi_enc_test_cmd_get` → `mpi_enc_test_cmd_update_by_args`. If parsing fails it prints the help, otherwise `mpi_enc_test_cmd_show_opt` ("cmd parse result: ...") runs, then `mpi_enc_test()`.
- `test_ctx_init` (0x13140):
  - Opens `/dev/mpi/valloc` (`open64`) and keeps the fd at ctx+1600.
  - If the input name starts with `/dev/video` (`strncmp(...,10)`), it calls `camera_source_init()`: V4L2 `VIDIOC_S_FMT`/`G_FMT`/`REQBUFS`/`QUERYBUF`/`QBUF`/`STREAMON`, `mmap64`, and DMA-buf export of the buffers imported with `mpp_buffer_import_with_tag` (strings "new framecap ok", "get dma buf(%d)-fd: %d", "VIDIOC_DQBUF").
  - Otherwise it opens the input file `rb` or prints "create default yuv image for test", then opens the output file `w+b`.
- `mpi_enc_test` (0x14e44):
  - Reads env `combo_en` and allocates frame and packet buffers (`mpp_buffer_get_with_tag`).
  - Calls `mpp_create`, then `mpp_init_ext` (the RV1106 kernel-channel init; the library exports `Mpp::init_ext(vcodec_attr_t*)` and talks to `/dev/vcodec`), then `mpp_enc_cfg_init` and `test_mpp_enc_cfg_setup`.
  - Calls `mpi_enc_create_jpegcomb` (creates a second MPP JPEG context for the "combo" snapshot), then `test_mpp_run`.
  - Prints "%p mpi_enc_test success total frame %d bps %lld" and cleans up with `mpp_destroy` and `mpp_enc_cfg_deinit`.
- `test_mpp_enc_cfg_setup` (0x13650) sets these keys with `mpp_enc_cfg_set_s32/u32`:
  - `prep:width/height/hor_stride/ver_stride/format/rotation/mirroring`
  - `rc:mode`, `rc:fps_in_*`, `rc:fps_out_*`, `rc:gop`, `rc:drop_*`, `rc:debreath_*` (from env `dbrh_en`/`dbrh_s`), `rc:bps_*`, `rc:qp_*`
  - `codec:type`, `h264:profile/level/cabac_en/cabac_idc/trans8x8`, `jpeg:q_factor/qf_max/qf_min`, `split:mode/arg` (env `split_mode`/`split_arg`)
  - It also reads env `gop_mode`, `osd_enable`, `osd_mode`, `roi_enable`, `user_data_enable`. Failure strings show the control calls it makes (set cfg, SEI, header mode, ref cfg).
- `test_mpp_run` (0x14370), per frame:
  - Gets the input from `read_image()` (file), `camera_source_get_frame()` + `camera_frame_to_buf()` (V4L2), or `fill_image()` (generated pattern).
  - Builds an `MppFrame` (`mpp_frame_set_width/height/hor_stride/ver_stride/fmt/pts/eos/buffer/jpege_chan_id`).
  - When OSD is enabled it calls `osd3_get_test_case` and `gen_smpte_bar_argb`, and attaches the user-data string "this is user data".
  - It puts the frame to the encoder. Packets are fetched through an `ioctl` on the valloc fd (cmd `0xC01C....`, a 28-byte `_IOWR`), `mmap64`'d, written to the output file with `fwrite`/`fflush`, then `munmap`/`close`d ("frame_count %d enc_packet.len %d, temporal_id %d").
  - Loops `-l` times per frame (`clearerr`/`rewind`) and stops at EOF or `-n`.
- `jpeg_comb_get_packet` (0x141bc), the JPEG combo/snapshot path: valloc `ioctl` → `mmap64`, then each JPEG is saved to `/sdcard/jpegen_out_%d_frm%d.jpeg` with `save_to_file` (`w+b`). The second `%d` is a per-context counter that increments each time.
- OSD helpers:
  - `gen_smpte_bar_argb` (0x1f7a8) opens `/userdata/wind_ABGR8888.ABGR8888` (`rb`, `fread`).
  - `mpi_enc_gen_osd_data3` (0x16ff0) opens `/sdcard/wind_ABGR8888.ABGR8888`, but no direct `bl` caller was found.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - `/dev/mpi/valloc` (opened directly; DMA buffer `ioctl` + `mmap`)
  - `/dev/video*` (V4L2 capture, only when given as `-i`)
  - `/dev/vcodec` (opened inside `librockchip_mpp` by `mpp_vcodec_open`)
- Files and paths read/written:
  - `-i` input (raw YUV/RGB/FBC) and `-o` output (H.264/H.265/MJPEG elementary stream)
  - `/sdcard/jpegen_out_%d_frm%d.jpeg` (JPEG combo snapshots, written)
  - `/userdata/wind_ABGR8888.ABGR8888` (OSD bitmap, read)
  - `/sdcard/wind_ABGR8888.ABGR8888` (OSD bitmap, read by `mpi_enc_gen_osd_data3`)
  - the optional `-x` ini file
- Network: none
- Environment variables / config files:
  - MPP env knobs read with `mpp_env_get_u32` (via `getenv` [INFERENCE]): `combo_en`, `dbrh_en`, `dbrh_s`, `split_mode`, `split_arg`, `gop_mode`, `osd_enable`, `osd_mode`, `roi_enable`, `user_data_enable`
  - the `-x` ini file

## Relevance on this camera

- Not started at boot. A word-match grep for `mpi_enc_test` over `etc/`, `oem/usr/etc/` and the `oem/usr/bin/*.sh` scripts finds nothing.
- The production app `/oem/usr/sbin/lp_app` links `librockchip_mpp.so.1` and `librockit.so` itself and does not reference this tool.
- It needs `mpp_vcodec.ko`, which `/oem/usr/ko/insmod_ko.sh` loads at boot.
- Running it while `lp_app` is streaming competes for the same VEPU540C encoder and kernel channels, and for camera nodes if `/dev/video*` is used. That could disturb or fail either program [INFERENCE].
- Side effects:
  - It writes the `-o` output file wherever the user points it.
  - In combo/JPEG mode it writes JPEGs to `/sdcard/...`. In the dump the SD card is mounted at `/mnt/sdcard` and no `/sdcard` exists, so those writes probably fail with "create file %s failed" [INFERENCE].
  - No flash, GPIO or reboot side effects.

## Evidence

```
$ readelf -d mpi_enc_test | grep NEEDED
 librockchip_mpp.so.1, libstdc++.so.6, libgcc_s.so.1, libc.so.0
$ llvm-nm-14 -D --defined-only mpi_enc_test   (exported, so the names survive stripping)
 main test_ctx_init test_mpp_enc_cfg_setup test_mpp_run mpi_enc_create_jpegcomb jpeg_comb_get_packet
 mpi_enc_test_cmd_update_by_args camera_source_init gen_smpte_bar_argb osd3_get_test_case iniparser_load ...
$ readelf -p .rodata mpi_enc_test
  [   a0]  /sdcard/jpegen_out_%d_frm%d.jpeg
  [  398]  /dev/mpi/valloc
  [  3bc]  /dev/video
  [  bc8]  /sdcard/wind_ABGR8888.ABGR8888
  [ 1bec]  /userdata/wind_ABGR8888.ABGR8888
  [  dc8]  rc_mode 0:vbr 1:cbr 2:avbr 3:cvbr 4:fixqp\n
# option switch
   162c8: sub r2, r3, #98        ; 'b'
   162d0: cmp r2, #22            ; .. 'x'
   162d4: addls pc, pc, r2, lsl #2
# -x: strnlen/malloc/strncpy then
   16414: bl 0x1dce4 <iniparser_load>
# main encoder setup (call order in mpi_enc_test)
   14ec4 mpp_env_get_u32("combo_en") -> 14efc/14f24 mpp_buffer_get_with_tag -> 14f3c mpp_create
   -> 14fa0 mpp_init_ext -> 14fb4 mpp_enc_cfg_init -> 14fc4 test_mpp_enc_cfg_setup
   -> 14fe0 mpi_enc_create_jpegcomb -> 14ff0 test_mpp_run
# jpeg_comb_get_packet: ioctl(valloc_fd, 0xC01C....) -> mmap64 -> snprintf("/sdcard/jpegen_out_%d_frm%d.jpeg") -> save_to_file
$ strings librockchip_mpp.so.0 | grep -E 'dev|vcodec'
 /dev/mpi/valloc  /dev/vcodec  mpp_vcodec_open  _ZN3Mpp8init_extEP13vcodec_attr_t
$ strings oem/usr/ko/mpp_vcodec.ko | grep jpege   -> hal_jpege_v540c ..., h264e/h265e chn attr
```

## Open questions

- The exact meaning of the first `%d` in `/sdcard/jpegen_out_%d_frm%d.jpeg`. It is an id held in the combo context, possibly the channel id [INFERENCE].
- Whether `/sdcard` exists on the running device. The dump has only `/mnt/sdcard`.
- The `-x` ini file is loaded, but no code that reads values from it was found. Its purpose (e.g. a hook left over from upstream) is unknown.
- `mpi_enc_gen_osd_data3` (reads `/sdcard/wind_ABGR8888.ABGR8888`) has no direct caller found. It may be reached through a function pointer or be dead code.
- The default coding type and frame size when `-t`/`-w`/`-h` are omitted were not traced.
- `-d` appears in help, but the jump table sends `d` to the "skip invalid opt" default. No other debug-flag path was found in this binary.
