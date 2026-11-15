# `vpu_api_test`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/vpu_api_test` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `13696` |
| sha256 | `6419fbc573244002ca8ed8ee38cbb6b7221a01498067b78a1837a0e6225f79ff` |
| linked libraries | `libc.so.0` |
| origin | Rockchip MPP test program `test/vpu_api_test.c` ("vpu api demo"; tests the legacy `libvpu` VpuApi compatibility layer) |
| confidence | high |

## Summary

This is MPP's legacy "vpu api demo". It loads `libvpu.so` with `dlopen` and uses the old Android-era `VpuCodecContext` API to decode a bitstream file to YUV420SP, or to encode a YUV file to a bitstream. `libvpu.so` is not present anywhere in the firmware dump, so on this camera the program can only print "failed to open libvpu.so" and exit. It is an unused SDK leftover.

## Usage

Help strings, verbatim. Short option names come from the option table in `.rodata` at 0x744 and after: `i`, `o`, `w`, `h`, `t`, `coding`, `vframes`, `ss`. The one-letter names `o`, `h` and `t` are stored as tails of merged strings.

```
usage: vpu_apiDemo [options] input_file, 

Getting help:
-help  --print options of vpu api demo
-i  input_file        input bitstream file
-o  output_file       output bitstream file, 
-w  width             the width of input bitstream
-h  height            the height of input bitstream
-t  codec_type        the codec type, dec: deoder, enc: encoder, default: decoder
-coding  coding_type  encoding type of the bitstream
-vframes  number      set the number of video frames to record
-ss  time_off         set the start time offset, use Ms as the unit.
```

- `-i`/`-o`: input and output file.
- `-w`/`-h`: picture size.
- `-t`: decoder or encoder, parsed with `atoi`. The code selects either the "decode" or the "encode" path.
- `-coding`: codec id number (`atoi`), e.g. an OMX/MPP coding type [INFERENCE].
- `-vframes`: frame limit.
- `-ss`: start offset.

Missing parameters print "Warning: missing needed parameters for vpu api demo".

## How it works

- It imports only libc plus `dlopen`/`dlsym`/`dlclose`; there is no direct link to MPP.
- Flow seen in the disassembly:
  1. Prints `/*******  vpu api demo in *******/`.
  2. `dlopen("libvpu.so")`, then `dlsym` of `vpu_open_context`, `vpu_close_context`, `VPUMemLink` and `VPUFreeLinear` ("get vpuapi handle %p ..."). If the open fails it prints "failed to open libvpu.so" and returns "vpu api demo fail, err: %d".
  3. Parses arguments (`strncmp`/`atoi`).
  4. Opens the input `rb` and the output `wb`.
  5. Decode path: reads packets ("read one packet, size: %d, pts: %lld, filePos: %ld"), sends them to the context, gets decoded frames and writes YUV420SP to the output file ("write %d frame(yuv420sp) data, %d bytes to file").
  6. Encode path: sets up the encoder with `VPU_API_ENC_SETFORMAT` / `VPU_API_ENC_GETCFG` / `VPU_API_ENC_SETCFG`, writes the SPS/PPS header ("encode init ok, sps len: %d"), reads YUV frames and writes the encoded output ("dump %d bytes enc output stream to file").
- The binary exports helper symbols `vpuapi_open_ctx`, `vpuapi_close_ctx`, `vpuapi_mem_link` and `vpuapi_mem_free`, which wrap the `dlsym`'d pointers.

## Interfaces touched

- Device nodes / sysfs / procfs: none directly. Any hardware access would happen inside `libvpu.so`, which does not exist here.
- Files and paths read/written: the `-i` input file (read) and the `-o` output file (written); `libvpu.so` (dlopen, resolved through the default library search path).
- Network: none
- Environment variables / config files: none found (apart from the loader's library search path).

## Relevance on this camera

- Not started at boot. A word-match grep of `etc/`, `oem/usr/etc/` and the `oem/usr/bin/*.sh` scripts finds nothing, and `lp_app` does not reference it.
- `find downlaods/3/dump -name 'libvpu*'` finds nothing, so the program fails right after start ("failed to open libvpu.so"). The dump has no `/usr/lib`, so a copy elsewhere on the live rootfs cannot be fully ruled out [INFERENCE: unlikely, since no binary in the dump links it].
- Even with the library present, this platform's `librockchip_mpp` is the RV1106 kernel-encoder variant (`mpp_vcodec`, VEPU540C encoder strings in `mpp_vcodec.ko`). The SoC is not expected to have a hardware video decoder [INFERENCE].
- No side effects beyond writing the `-o` file.

## Evidence

```
$ readelf -d vpu_api_test | grep NEEDED
 0x00000001 (NEEDED)  Shared library: [libc.so.0]
$ llvm-nm-14 -D --undefined-only vpu_api_test
 ... dlclose dlopen dlsym fopen64 fread fwrite ... (no MPP symbols)
$ readelf -p .rodata vpu_api_test
  [    34]  libvpu.so
  [    40]  failed to open libvpu.so
  [    5c]  vpu_open_context
  [    70]  vpu_close_context
  [    84]  VPUMemLink
  [    90]  VPUFreeLinear
  [   6e0]  usage: vpu_apiDemo [options] input_file, \n
  [   744]  i
  [   748]  input_file
# call order in main: 10ad4 dlopen("libvpu.so") -> 10af8.. dlsym x4 -> argument parsing -> fopen64 rb/wb
$ find downlaods/3/dump -name 'libvpu*'
 (no output)
```

## Open questions

- The numeric values `-t` and `-coding` expect: upstream uses 1 for decode and 2 for encode, and OMX coding numbers [INFERENCE]. The constants were not traced in the disassembly.
- Whether a `libvpu.so` could exist on a partition missing from this dump (`/usr/lib` is not in the dump).
