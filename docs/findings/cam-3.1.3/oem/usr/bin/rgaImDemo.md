# `rgaImDemo`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rgaImDemo` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `17976` |
| sha256 | `eca9d5e3b2d86b5ab9f3400a30c11bf8058e299c1904ef412a397a64e43c24d4` |
| linked libraries | `librga.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip librga sample `samples/im2d_api_demo` (`rgaImDemo`), built against librga `rga_api version 1.8.1_[4]` |
| confidence | high |

## Summary

This is the demo/test tool for the RGA 2D graphics accelerator's im2d API. Each run performs one RGA operation on a 1280×720 test image: copy, resize, crop, rotate, flip, translate, blend, colour conversion or fill. It can also query RGA version and capabilities. It is an SDK test tool, not used by the production app.

## Usage

Verbatim help text (`help_function()`, 0x123b4):

```
=============================================================================================
   usage: rgaImDemo [--help/-h] [--while/-w=(time)] [--querystring/--querystring=<options>]
                    [--copy] [--resize=<up/down>] [--crop] [--rotate=90/180/270]
                    [--flip=H/V] [--translate] [--blend] [--cvtcolor]
                    [--fill=blue/green/red]
	 --help/-h     Call help
	 --while/w     Set the loop mode. Users can set the number of cycles by themselves.
	 --querystring You can print the version or support information corresponding to the current version of RGA according to the options.
	               If there is no input options, all versions and support information of the current version of RGA will be printed.
	               <options>:
	               vendor       	Print vendor information.
	               version      	Print RGA version, and librga/im2d_api version.
	               maxinput     	Print max input resolution.
	               maxoutput    	Print max output resolution.
	               scalelimit   	Print scale limit.
	               inputformat  	Print supported input formats.
	               outputformat 	Print supported output formats.
	               expected     	Print expected performance.
	               all          	Print all information.
	 --copy        Copy the image by RGA.The default is 720p to 720p.
	 --resize      resize the image by RGA.You can choose to up(720p->1080p) or down(720p->480p).
	 --crop        Crop the image by RGA.By default, a picture of 300*300 size is cropped from (100,100).
	 --rotate      Rotate the image by RGA.You can choose to rotate 90/180/270 degrees.
	 --flip        Flip the image by RGA.You can choice of horizontal flip or vertical flip.
	 --translate   Translate the image by RGA.Default translation (300,300).
	 --blend       Blend the image by RGA.Default, Porter-Duff 'SRC over DST'.
	 --cvtcolor    Modify the image format and color space by RGA.The default is RGBA8888 to NV12.
	 --fill        Fill the image by RGA to blue, green, red, when you set the option to the corresponding color.
=============================================================================================
```

Option table: the `struct option` array at `.data` 0x2409c, parsed with `getopt_long`. The short option string is `"hw:"`, built on the stack as `0x003a7768`.

| long option | has_arg | val | im2d call |
|---|---|---|---|
| `--querystring[=opt]` | optional | `'0'` | `querystring()`. Options: `vendor`, `version`, `maxinput`, `maxoutput`, `scalelimit`, `inputformat`, `outputformat`, `expected`, `all`, plus the one-letter aliases `v`, `i`, `o`, `s`, `u`, `a` found among them in `.rodata` (which alias belongs to which keyword is [INFERENCE] from string order) |
| `--copy` | no | `'1'` | `imcopy` |
| `--resize=up\|down` | required | `'2'` | `imresize`. `up` gives 1920×1080, `down` gives 720×480 |
| `--crop` | no | `'3'` | `imcrop` (300×300 at 100,100) |
| `--rotate=90\|180\|270` | required | `'4'` | `imrotate` |
| `--flip=H\|V` | required | `'5'` | `imflip` |
| `--translate` | no | `'6'` | `imtranslate` (300,300) |
| `--blend` | no | `'7'` | `imblend` (SRC over DST) |
| `--cvtcolor` | no | `'8'` | `imcvtcolor` (RGBA8888 to NV12) |
| `--fill=blue\|green\|red` | required | `'9'` | `imfill` |
| `--help` / `-h` | no | `'h'` | help |
| `--while=N` / `-w N` | required | `'w'` | repeat the operation N times ("This is %d time in the loop"). A zero value gives "Option must be a non-zero number." |

## How it works

`main` (0x10eb0) calls `readArguments()`, which uses `getopt_long`, `readParm()` and `readInfo()` ("Start selecting mode %x", "MODE = %x"). Then, for an image operation:

1. `malloc` source and destination buffers of 1280×720 × `get_bpp_from_format()`.
2. `get_buf_from_file(src, fmt, 1280, 720, 0)` loads the source image (printing "open file" or "can not open file"). Blend and fill also load the destination with index 1. The librga helper builds the path `/usr/data/in%dw%d-h%d-%s.bin`.
3. Wrap the buffers with `importbuffer_virtualaddr()` and `wrapbuffer_handle()` ("Failed to import virtualaddr for src/dst channel!").
4. Run `rga_check_perpare()` and `imcheck_t()` ("%d, check error! %s").
5. Read `gettimeofday`, call the `im*()` operation, read `gettimeofday` again, and print e.g. "copying .... cost time %ld us, %s" with `imStrError_t()`.
6. Write the result with `output_buf_data_to_file(dst, fmt, w, h, 0)` (`/usr/data/out%dw%d-h%d-%s.bin`), then `releasebuffer_handle()` and `free()`.

The hardware access happens inside `librga.so`, which opens `/dev/rga` (or `/dev/dri/card0`) and issues the `RGA_BLIT`/`RGA_COLORFILL`/`RGA_IOC_IMPORT_BUFFER` ioctls.

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/rga` (via `librga.so`; also `/dev/dri/card0` in the library). The `rga3.ko` driver is loaded at boot by `/oem/usr/ko/insmod_ko.sh`.
- Files and paths read/written:
  - read: `/usr/data/in0w1280-h720-<fmt>.bin`, plus `in1...` for the destination of blend/fill
  - written: `/usr/data/out0w<W>-h<H>-<fmt>.bin`
  - The exact `<fmt>` text, e.g. `rgba8888`, is filled in by librga [INFERENCE].
- Network: none
- Environment variables / config files: none in the binary.

## Relevance on this camera

- Not started at boot and not referenced by any init script.
- The production app `/oem/usr/sbin/lp_app` links `librga.so` directly, and `librockit.so` links it too, so the RGA hardware is in use at runtime. RGA jobs from several processes are scheduled by the kernel driver, so running the demo alongside `lp_app` should work but adds load [INFERENCE].
- The dump has no `/usr/data`. Without the input files, `get_buf_from_file` prints "can not open file" and the operation runs on uninitialised or zeroed buffers; the output write would also fail [INFERENCE].
- No flash, GPIO or reboot side effects.

## Evidence

```
$ llvm-nm-14 -D -C rgaImDemo | grep ' U '
 imcopy imresize imcrop imrotate imflip imtranslate imblend imcvtcolor imfill querystring
 importbuffer_virtualaddr wrapbuffer_handle releasebuffer_handle get_buf_from_file
 output_buf_data_to_file get_bpp_from_format imcheck_t imStrError_t rga_check_perpare getopt_long
$ readelf -x .data rgaImDemo   (struct option: name, has_arg, flag, val)
  3c390100 02000000 00000000 30000000  -> "querystring",2,0,'0'
  48390100 00000000 00000000 31000000  -> "copy",0,0,'1'   ... "fill",1,'9'  "help",0,'h'  "while",1,'w'
   128ac: movw r3, #30568 ; movt r3, #58   -> "hw:"
   11f8c..11fa0: r2=#1280 r3=#720 [sp]=0 -> bl get_buf_from_file
   11f38: movw r3,#1080 ; mov r2,#1920      (resize up)
$ strings librga.so | grep -E '/data|/dev|version'
 /usr/data/in%dw%d-h%d-%s.bin  /usr/data/out%dw%d-h%d-%s.bin  /dev/rga  /dev/dri/card0  rga_api version 1.8.1_[4]
$ grep -n rga3 oem/usr/ko/insmod_ko.sh
36:__insmod rga3.ko
```

## Open questions

- Source and destination pixel formats for each mode were not fully traced. The help states RGBA8888 by default, and NV12 output for `--cvtcolor`.
- Whether `/usr/data` exists on the live root filesystem; it is not in the dump.
- Which mode letter maps to which internal `MODE` value beyond the `getopt_long` `val` characters.
