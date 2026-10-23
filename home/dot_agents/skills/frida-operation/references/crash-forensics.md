# Crash forensics on iOS (.ips)

Every crash lands in `/var/mobile/Library/Logs/CrashReporter/<Proc>-<date>.ips` (rootless:
also `/var/jb/var/mobile/Library/Logs/CrashReporter/`). The file is **two JSON documents**:

```
{ "app_name": ..., "bug_type": "309", "timestamp": ... }      <- header, one line
{ "procName": ..., "exception": {...}, "threads": [...], "usedImages": [...] }  <- body
```

`scripts/crash_map.py` reads both, resolves the fault address against `usedImages`
(base + size window), and prints the faulting thread's frames. Use `--json` when you need
to diff several reports.

## Reading the numbers

- `exception.codes` = `"<code>, <subcode>"`; the **subcode** is usually the fault address
  (in hex). `0xffffffffffffffff` means "no address" — typical for a deliberate
  `SIGILL`/`SIGBUS` raised by the target itself, or a jump through a poisoned pointer
  (`blr x8` with `x8 = -1`).
- `termination.indicator` = the human summary (`Illegal instruction: 4`, `Bus error: 10`).
- `threads[faultingThread].frames[]` carries `imageIndex` + `imageOffset`; symbol names are
  present for Apple binaries and absent for stripped third-party ones — that is why the
  base+offset mapping matters.
- `usedImages` includes every mapped image, including injected dylibs and the dyld shared
  cache; a fault "inside" a cache image is really inside the OS library at that offset.

## Signal → cause

| Signal / exception | Usual cause |
| --- | --- |
| `EXC_BREAKPOINT` / `SIGILL` at `dyld4::RuntimeState::notifyObjCInit` | Frida spawn-injection into an encrypted App Store app |
| `EXC_BAD_ACCESS` / `SIGBUS`, `codes 0x2` | use-after-free / dangling object (objects from heap scans that were never retained) |
| `EXC_BREAKPOINT` / `SIGTRAP` in `_dispatch_once_wait` | recursive `dispatch_once` (a once-block synchronously notifying an observer that re-enters) |
| `SIGSEGV` at a small odd address (`0x1`, `0x2`, `0x5f0a1b2c`) | an integer/handle messaged as an object (`objc_retain`/`objc_msgSend`) |
| `EXC_BAD_ACCESS` / `SIGBUS KERN_PROTECTION_FAILURE` in `__TEXT` | a signed code page was modified at runtime (CS invalidation on re-fault) |
| `EXC_CRASH` / `SIGKILL` with `namespace SIGNAL, code 9` | watchdog / jetsam / `kill -9` from another process |

## Habits that pay off

- `grep` the report for `frida`, `gum-js`, `Stalker` thread names to know whether the
  crash happened while attached.
- If the crash address equals a *value* you were handling (a timestamp, a row id), you
  have a type-confusion bug, not a memory bug — check the method's type encoding.
- When a target "silently disappears", compare `enumerate_processes()` before/after and
  read the newest `.ips`; a `process-terminated` detach reason plus no new report means a
  clean exit, not a crash.
