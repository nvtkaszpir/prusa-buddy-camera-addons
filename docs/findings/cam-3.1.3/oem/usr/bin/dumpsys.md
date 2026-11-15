# `dumpsys`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/dumpsys` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `38656` |
| sha256 | `0619316e97f53cb3dca35e58273dacc3daa43cd71b854cd63251cd50f073c9be` |
| linked libraries | `libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip rockit (RK MPI) debug tool "dumpsys" (self-reported `dumpsys version: v2.0`), shipped with the RV1106 SDK rockit package. It is a client for the dump server built into `librockit.so`. |
| confidence | high |

## Summary

`dumpsys` is Rockchip's rockit/MPI debug client. It connects to the dump server that `librockit.so` starts inside `RK_MPI_SYS_Init()` on `tcp://127.0.0.1:3893`. It sends a request of the form `/rockit/mpi/dump#<json>#` and prints the server's text reply between `DUMP OF SERVICE` / `END DUMP OF SERVICE` banners. The reply covers module and channel state: VI, VENC, VPSS, RGN, MB (memory blocks), SYS bindings, audio, TDE and so on. The tool can also do a few local-only dumps (library versions, clock frequencies, memory). It was presumably shipped to debug the media pipeline of the production app `lp_app`, which links `librockit.so`. However, a live check on the camera found no listener on 127.0.0.1:3893 while `lp_app` was running, so the remote dumps do not work against the running app as observed (see "Relevance on this camera").

## Usage

The usage text is embedded verbatim (including the typo "moudle"):

```
usage: 
         dumpsys [moudle] [moudle ARGS] [--uri uriName] [uri ARGS] 
         --help: shows this help
         --uri uriName: register service base on uriName 
         [uri ARGS]: optionally passing ARGS to service 
         moudle [moudle ARGS]: dumps only module, optionally passing ARGS to it
```

Options are parsed with `getopt_long(argc, argv, "+", longopts, &idx)`. The `+` stops parsing at the first non-option, so options must come before the module name. The long-option table at `.data` 0x27128 was decoded from the binary:

| option | arg | effect (from `Dumpsys::start` disassembly) |
|---|---|---|
| `--uri <name>` | required | Replaces the default service name `dump` with `<name>`, so the request becomes `/rockit/mpi/<name>#...#`. It also clears the "first positional = module" flag, so every positional argument goes into `"uriArgs"`. |
| `--version` | none | Local version report (see below). Plain `dumpsys version` does the same. |
| `--list` | none | Sets the flag passed to `DumpVersion::dumpSetDumpList(bool)`. It only matters together with `--version`. [INFERENCE] It probably prints every matching version line instead of only the first. |
| `--freq` | none | Local CPU/VPU/GPU/RGA clock report (`DumpMemory::dumpModuleFreq`). |
| `--mem` | none | Local memory report (`DumpMemory::dumpMemoryInfo`). |
| `--help` | none | Prints the usage to stderr and exits 0. Unknown options also print the usage. |

Positional forms that are sent to the rockit dump server:

- `dumpsys` with no arguments sends module `all`, which dumps every registered module.
- `dumpsys <module> [args...]` dumps one module. The server resolves the name through rockit's module-ID table, which is embedded in `librockit.so` and `simple_fast_client`: `cmpi mb sys rgn venc vdec vpss vgs vi vo ai ao aenc adec tde isp wbc avs rga af ivs`. Only modules that are actually instantiated in the target process produce output.
- `dumpsys all` dumps all registered modules.
- `dumpsys record [opts]` is handled by the server-side "record" sub-parser. Usage string from `librockit.so`: `./dumpsys record [-m MOD] [-d DEVID] [-c CHNID] [-o OUTPUT FILE]...`. Options, with short letters taken from the server's option table: `-m/--mod` "module name. <required on record>", `-d/--dev` "device id. <required on record>", `-c/--chn` "channel id. <required on record>", `-n/--count` "record count <required on record>", `-o/--output` "record file name.", `-i/--is_input` "record input/output stream(0: output, 1: input)", `--help` "show this help message and exit". The server replies "start record data success..." or "process record data failed.".
- `dumpsys tde record_begin <dir> <num>` is a module-specific argument of the TDE dump handler. The server string reads `args not enough when record in. eg: dumpsys tde record_begin /tmp/ 10`, followed by `record begin, path %s, num:%d`.

Section titles the server can return (strings in `librockit.so`) include: `bind relation table` (sys), `mb channel info`, `mb detail info`, `mb module info` (mb), `vi chn attr`, `vi chn get buf state` (vi), `vpss chn crop info`, `vpss chn work status`, `vpss group crop info`, `vpss group pic info` (vpss), `region chn status of cover/mosaic/overlay` (rgn), `tde job status`, `tde task status` (tde), `ai/ao/aenc/adec chn attr/status`, and `ai/ao dev extend status`.

## How it works

The binary keeps its C++ symbols even though it is "stripped", so the classes `Dumpsys`, `DumpClient`, `DumpVersion` and `DumpMemory` are visible.

1. `main` calls `signal(SIGPIPE, SIG_IGN)`, then `new Dumpsys` and `Dumpsys::start(argc, argv)`. The constructor sets the default service name `"dump"` (string at 0x15f94) and "first positional is module" = 1.
2. `Dumpsys::start` runs the `getopt_long` loop above. Local paths:
   - `--freq` runs `DumpMemory::dumpModuleFreq`. It uses `popen` (via `executeCMD`) on `cat /sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq`, `cat /sys/kernel/debug/clk/clk_summary | grep vdec`, `cat /sys/kernel/debug/clk/clk_scmi_gpu/clk_rate`, `cat /sys/devices/platform/fde60000.gpu/utilisation` and `cat /sys/kernel/debug/clk/clk_summary | grep -E rga`.
   - `--mem` runs `DumpMemory::dumpMemoryInfo`, which executes `cat sys/kernel/debug/dri/0/mm_dump | grep total/used/free` (a relative path) and `free`.
   - `--version` / `version` runs `DumpVersion::dumpModuleVersion`. `getLibPath` runs `export | grep LD_LIBRARY_PATH` and falls back to `/oem/usr/lib`, `/usr/lib`, `/vendor/lib`, `/system/lib`. It then prints `dumpsys version: v2.0` and greps library files for version markers:
     - `librockit.so`: `git-`, `built-`
     - `librockchip_mpp.so.1`: `author`
     - `librga.so.2`: `2021`, `rga_api`
     - `librkgfx_avs.so`: `GPU_AVS_DEBUG_LOG -A 1`
     - It also runs `cat /proc/mpp_service/version` and `cat /tmp/gpu_version`.

     The greps use an in-process `strings()` (fopen/getc) or `popen("strings %s | grep %s ...")`.

3. Remote path:
   - The positional arguments go into two vectors, module names and arguments. `Dumpsys::generateJson` builds `{"module":"<name>", "moduleArgs":["a",...]}`, or `{"uriArgs":[...]}` in `--uri` mode.
   - `InitDumpClient` calls `DumpClient::sockClientOpen("tcp://127.0.0.1:3893")`. `urlSplit` parses proto/host/port. `tcp` uses `socket`+`connect` to 127.0.0.1:3893; `domain` would use an AF_UNIX path.
   - `DumpClientSendModule` formats `snprintf(buf, 1024, "/rockit/mpi/%s#%s#", uri, json)` and calls `DumpClient::sendDump(5, buf, 1024)`.
   - `DumpClientReceiveDump` → `receiveDumpMessage` (size header) → `receiveDump` (body, via `recv`).
   - `writeDumpToStd` prints the reply framed by a dashed line, `DUMP OF SERVICE %s:` and `END DUMP OF SERVICE %s:`.
   - If the send fails, it prints `start: Confirm MPI system has been initialized and running?`.
4. Server side (not in this binary): `librockit.so` `RK_MPI_SYS_Init` (0x541a8) → 0x4e4ec → `bl 0x7d65c` → `b 0x7d4d0`. That function references `tcp://127.0.0.1:3893` and `ipcs_server`. The class is `RKSockServer` (`binding to host:%s, port:%d`, `client connected. waiting for msg...`). The dispatcher (decoded in the identical statically linked copy inside `simple_fast_client`) compares `module` against `"all"` (dump every module) and `"record"` (record parser). Otherwise it maps the name to a module ID with a `strcmp` loop over the 21-entry table `cmpi…ivs`, then calls that module's dump method.
   - Start-up chain and its guards, from the disassembly:
     - `RK_MPI_SYS_Init` (0x4e4ec) only checks its own once-flag (a global that it sets to 1 and that `RK_MPI_SYS_Exit` clears). It then calls 0x7d65c without any other condition.
     - 0x7d4d0 returns at once if the server global (0xfa140) is already set. Otherwise it creates the server with `new` + ctor 0x7e874("tcp://127.0.0.1:3893") and starts an `RtThread` named `ipcs_server` whose entry (0x7d4b8) calls the server's `run` method.
     - The ctor parses the URI (`proto:%s, hostname:%s, path:%s, port:%d`). For `tcp` it calls 0x7ddb0, which:
       - checks that the port is in 1..65535;
       - calls `socket(AF_INET, SOCK_STREAM, 0)`, `setsockopt(SOL_SOCKET, SO_REUSEADDR)` and `bind` to `inet_addr(host)`;
       - on failure logs `socket(...) failed` / `bind failed, reason: %s` through rockit's own logger, closes the fd and continues without a server socket.
       For `domain` it would use an AF_UNIX path instead (0x7dfb4).
     - `run` (vtable slot 2 = 0x7eb98) logs `sock server not initialized` if the fd is < 0. Otherwise it calls `listen(fd, 1)` and loops `select` → `accept` → handle message.
     - No environment variable, property or config file is read anywhere on this path. The library's only `getenv` callers (0xb5734, 0xb57c0, generic env helpers) are not reached from it.
     - Teardown: `RK_MPI_SYS_Exit` (0x541ac → 0x4e560) calls 0x7d660 → 0x7d588, which stops and joins the thread, deletes the server (closing the socket) and clears 0xfa140.
     - So in `librockit.so` the listener exists exactly while a process sits between a successful `RK_MPI_SYS_Init` and `RK_MPI_SYS_Exit`, provided `socket`/`bind` succeeded. There is no opt-in switch.

## Interfaces touched

- Device nodes / sysfs / procfs, all read via `popen("cat ...")`, local modes only:
  - `/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq`
  - `/sys/kernel/debug/clk/clk_summary`
  - `/sys/kernel/debug/clk/clk_scmi_gpu/clk_rate`
  - `/sys/devices/platform/fde60000.gpu/utilisation`
  - `sys/kernel/debug/dri/0/mm_dump` (relative path)
  - `/proc/mpp_service/version`
- Files and paths read/written:
  - Reads (version mode): `/oem/usr/lib`, `/usr/lib`, `/vendor/lib` or `/system/lib` plus `librockit.so`, `librockchip_mpp.so.1`, `librga.so.2`, `librkgfx_avs.so`, and `/tmp/gpu_version`.
  - Writes nothing itself. It imports `unlink` (presumably for an AF_UNIX socket path). The server-side `record` command makes the target process write the file given with `-o` or the `tde record_begin` path.
- Network: TCP client to `127.0.0.1:3893` (loopback only). The protocol is a length-prefixed message carrying `/rockit/mpi/<uri>#<json>#`, with type 5 = dump.
- Environment variables / config files: `LD_LIBRARY_PATH`, read through `popen("export | grep LD_LIBRARY_PATH")`.

## Relevance on this camera

- `dumpsys` is not started at boot. `grep -r dumpsys` over `downlaods/3/dump/` finds only the binary itself, `librockit.so` (the server's help text) and `simple_fast_client` (a static copy of that server).
- Live observation: with `lp_app` running (pid 357, `lp_app --noshell --log2file /mnt/sdcard/logs`), `netstat -ln` on the camera shows no listener on 127.0.0.1:3893. The only listeners are RTSP :554, dropbear :22, `busybox telnetd` :23, and the Unix sockets `/tmp/UNIX.domain` and `/run/udev/control`. As observed, `dumpsys <module>` therefore cannot reach `lp_app`. It can only fail with `Confirm MPI system has been initialized and running?`. The local `--version` / `--freq` / `--mem` modes still work.
- Why the listener is missing is not explained by the dumped binaries:
  - In `librockit.so` the listener has no opt-in switch: no environment variable, property or config file is read on that path (see "How it works", step 4). It exists while the process is between a successful `RK_MPI_SYS_Init` and `RK_MPI_SYS_Exit`, if `socket`/`bind` succeed.
  - The dumped `lp_app` imports `RK_MPI_SYS_Init` and calls it once, at 0x66f58 in `init` (`lp_rv1106_dev.cpp`, right after the `mWorkModeH264: %d, resolution: %dx%d` log). If that call fails it logs `RK_MPI_SYS_Init failed!` and calls `RK_MPI_SYS_Exit`. `RK_MPI_SYS_Exit` is also called at 0x66500 in `deinit`, just before `deinit end!!!!!`.
  - So by static analysis the dumped `lp_app` + `librockit.so` should listen after `init`. The guarding condition that suppresses it on the live device is **unknown**.
  - Candidate explanations, all [INFERENCE]:
    1. The running `lp_app` is a different build than the one in `downlaods/3/dump/`. Only the `downlaods/2` log shows `init` at source line 297, which matches the dumped binary (`movw r3, #297` before the call). The later logs (`downlaods/6`, `7`, `8`, `sdcard/logs/2026-02-*`) show `lp_rv1106_dev.cpp:437 init`, so a newer `lp_app`, and possibly a newer `librockit.so`, runs now.
    2. `lp_app` ran `deinit` (→ `RK_MPI_SYS_Exit`, which deletes the server) and did not reach `init` again. The logs do contain `deinit | deinit end!!!!!` entries.
    3. `socket`/`bind` failed. That error goes to rockit's own logger, not to `lp_app`'s log file.
- What would be needed to use it: an `lp_app` process that has passed `RK_MPI_SYS_Init` without a later `RK_MPI_SYS_Exit`, with the server bound. Nothing in the dumped `librockit.so` can switch it on from outside. [INFERENCE] If explanation 2 applies, restarting `lp_app` should bring the listener up. If explanation 1 applies, the newer binaries have to be pulled and analysed. Possible device checks (read-only):
  - `grep ' 0100007F:0F35 ' /proc/net/tcp` (port 3893 = 0x0F35);
  - thread names in `/proc/357/task/*/comm` (look for `ipcs_server`);
  - `md5sum /oem/usr/sbin/lp_app /oem/usr/lib/librockit.so`, compared against the dump.
- Result of those checks on the live camera (read-only, over ssh):
  - `lp_app` on the device is a **different build** from the dumped one: md5 `ee845fa0b2e4a8cc0eaf5d7135b8f144` (4765884 bytes) vs dump `97d3fc7d71dd8d45527bcefd3b352748`. `librockit.so` is **identical**: `63e0b581e4d41e66177e31ed1a818e64` on both.
  - The live `lp_app` (pid 357) runs a full pipeline. Its threads include `vi-0`, `venc-0`, `venc-1`, `ai-0`…`ai-4`, `NOTICECENTER_00/01`, `config_thread`, and the rkaiq threads `xc:RkAiqCoreThr`, `xc:isp_3a_stats`, and others. So `RK_MPI_SYS_Init` has run, and the process is not stuck after a `deinit`. **Explanation 2 is ruled out.**
  - There is **no `ipcs_server` thread**, and `/proc/net/tcp` has no `0100007F:0F35` entry.
  - Conclusion: with an identical `librockit.so`, whose `RK_MPI_SYS_Init` creates the `ipcs_server` thread with no extra guard, the missing thread points either to `socket`/`bind` failing at start-up or to the newer `lp_app` initialising MPI in a way the dumped build does not [INFERENCE]. A failed bind would still create and name the thread, and `run` would then return on `fd<0`, so the thread could exit. Telling these apart needs rockit's own log output or analysis of the newer `lp_app`, which can be pulled with `rsync`/`scp` from `/oem/usr/sbin/lp_app`.
- `/tmp/UNIX.domain` (the AF_UNIX listener that is present) has nothing to do with this dump server. The string is not in `lp_app` or `librockit.so`. In the dump, only `oem/usr/lib/librkaiq.so` contains it (next to `E:Error bind %s` / `E:Error listen`, the rkaiq tuning socket server; `busybox` and `udhcpd` only have the unrelated "Active UNIX domain sockets" text). `lp_app` has `NEEDED librkaiq.so`, so [INFERENCE] the socket is created by `librkaiq.so` inside `lp_app`.
- Side effects: the plain dump commands are read-only. `dumpsys record ...` and `dumpsys tde record_begin ...` make `lp_app` write stream or frame data to a file, which can fill `/tmp` or the SD card.
- `--freq` / `--mem` / `--version` are local and harmless. Most of their paths target other Rockchip SoCs (GPU at `fde60000`, `clk_scmi_gpu`, DRM `mm_dump`), so on the RV1106 they will print empty results or `cat` errors. [INFERENCE]

## Evidence

- `readelf -d dumpsys`: NEEDED `libstdc++.so.6`, `libgcc_s.so.1`, `libc.so.0`.
- Imports: `socket connect send recv getopt_long popen pclose fopen getc access inet_addr strtok_r signal unlink`.
- `strings -t x dumpsys` (.rodata):
  ```
  5d2b module   5d36 , "moduleArgs":[   5d47 {"uriArgs":[
  5d59 tcp://127.0.0.1:3893
  5d6e END DUMP OF SERVICE %s:
  5dd8 /rockit/mpi/%s#%s#
  5f23 uri  5f27 list  5f2c mem  5f30 all  5f94 dump
  5f34 Confirm MPI system has been initialized and running?
  617f dumpsys version:  6190 v2.0
  ```
- Long-option table `.data` 0x27128 (name, has_arg): `uri`,1 / `version`,0 / `list`,0 / `freq`,0 / `mem`,0 / `help`,0. Optstring `"+"` is at 0x15deb.
- `Dumpsys::start` (0x13b64): `strcmp(name,"help")` → print usage; `"uri"` → `this->uri = optarg; this->moduleMode = 0`; `"version"`/`"list"`/`"freq"`/`"mem"` set flags at +329/+330/+331/+332. Then `generateJson` → `InitDumpClient` → `DumpClientSendModule` → `DumpClientReceiveDump` → `writeDumpToStd`.
- `Dumpsys::DumpClientSendModule` (0x134b0): `snprintf(buf,1024,"/rockit/mpi/%s#%s#",...)` followed by `DumpClient::sendDump(this->client, 5, buf, 1024)`.
- `librockit.so` strings: `tcp://127.0.0.1:3893`, `ipcs_server`, `/rockit/mpi/dump`, `RKSockServer`, `binding to host:%s, port:%d`, `./dumpsys record [-m MOD] [-d DEVID] [-c CHNID] [-o OUTPUT FILE]...`, `args not enough when record in. eg: dumpsys tde record_begin /tmp/ 10`.
- `librockit.so` disassembly: `RK_MPI_SYS_Init` (0x541a8) → `b 0x4e4ec`, which contains `bl 0x7d65c`. 0x7d65c is `b 0x7d4d0`, and that function resolves `tcp://127.0.0.1:3893` (at 0x7d504) and `ipcs_server` (at 0x7d550).
- `librockit.so` dump-server chain (`llvm-objdump -d --triple=armv7-linux-gnueabihf`):
  ```
  4e4f8 cmp r2,#0 ; bne 4e554       ; once-flag only, no other guard in SYS_Init
  4e518 bl 0x7d65c                  ; -> b 0x7d4d0, unconditional
  7d4e8 cmp r3,#0 ; bne 7d560       ; server global 0xfa140 already set -> return
  7d508 bl 0x7d748                  ; new RKSockServer("tcp://127.0.0.1:3893") -> ctor 0x7e874 -> 0x7e77c (URI parse)
  7e80c strcmp(proto,"tcp") ; 7e824 bl 0x7ddb0   ; else strcmp(proto,"domain") -> 0x7dfb4
  7de4c socket(2,1,0) ; 7de90 setsockopt(...,1,2,...) ; 7def4 bind ; failure -> log + close
  7d540 RtThread(0x7d4b8, server) ; 7d554 setName("ipcs_server") ; 7d55c start
  7eb98 run: fd<0 -> "sock server not initialized" ; 7ebf0 listen(fd,1) ; 7ec78 accept loop
  4e5b4 (SYS_Exit) bl 0x7d660 -> 0x7d588: stop/join thread, delete server, clear 0xfa140
  ```
  PLT targets: `listen` 0xd50c, `bind` 0xd8fc, `socket` 0xd920, `accept` 0xdadc, `getenv` 0xdb24 (callers only 0xb5734 and 0xb57c0, not on this path).

- `readelf -d oem/usr/sbin/lp_app`: NEEDED includes `librockit.so` and `librkaiq.so`.
- `lp_app` (`llvm-nm-14 -D --undefined-only`): imports `RK_MPI_SYS_Init` (PLT 0x1ad54) and `RK_MPI_SYS_Exit` (PLT 0x1c0ec). Call sites:
  - 0x66f58 `bl RK_MPI_SYS_Init` in `init`; 0x66f8c `RK_MPI_SYS_Exit` on its failure path (`RK_MPI_SYS_Init failed!`);
  - 0x66500 `RK_MPI_SYS_Exit` in `deinit` (`deinit end!!!!!`).
  `lp_app` has no `3893`, `ipcs` or `UNIX.domain` strings.
- Live device, `netstat -ln` while `lp_app` (pid 357) runs:
  ```
  tcp  0.0.0.0:554  LISTEN      (RTSP)
  tcp  0.0.0.0:22   LISTEN      (dropbear, added by user)
  tcp  0.0.0.0:23   LISTEN      (busybox telnetd)
  unix STREAM  LISTENING /tmp/UNIX.domain
  unix SEQPACKET LISTENING /run/udev/control
  ```
  There is no 127.0.0.1:3893 entry.

- `grep -rla UNIX.domain downlaods/3/dump`: `bin/busybox`, `oem/usr/sbin/udhcpd` (netstat header text only), and `oem/usr/lib/librkaiq.so` (`f3362 /tmp/UNIX.domain`, followed by `E:Error bind %s`, `E:Error listen`).
- Build drift: `grep -o 'lp_rv1106_dev.cpp:[0-9]* init | mWorkModeH264'` gives line 297 only in `downlaods/2/logs/1970-01-01_00.log`, and line 437 in `downlaods/6,7,8/logs` and `sdcard/logs/2026-02-*`.

## Open questions

- Why `lp_app` on the live camera has no 127.0.0.1:3893 listener and no `ipcs_server` thread, although it runs a full MPI pipeline with the same `librockit.so` as the dump. A `deinit` without re-`init` is ruled out by the live thread list. What remains is a start-up `socket`/`bind` failure (the thread would then exit after `run` sees `fd<0`), or different MPI initialisation in the newer live `lp_app` build (md5 `ee845fa0…`, not in the dump).
- The exact set of argument strings each module's dump handler accepts (besides `tde record_begin`) is buried in stripped rockit code and was not enumerated.
- Which modules support the server-side `record` command, and what file format each writes, was not traced.
- `--list` semantics: [INFERENCE] they switch the version grep to "print all matches".
