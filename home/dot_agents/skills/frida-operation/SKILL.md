---
name: frida-operation
description: >-
  Operate Frida 17+ from Python host agents across iOS and mobile runtimes.
  Use this skill when dynamically instrumenting apps, debugging lifecycles without sleeps,
  implementing RPC protocols, performing bridge-free ObjC introspection, triaging crashes (.ips),
  bypassing integrity/anti-tamper checks (IMP swizzling), or inspecting StoreKit/IAP.
---

# Frida 17+ Operation Guide: Event-Driven & Bridge-Free Architecture

The primary failure mode in dynamic instrumentation is managing lifecycle and synchronization. Relying on `time.sleep(N)` or fragile CLI pipelines (`frida | head`) introduces race conditions, pipe buffer deadlocks (`SIGPIPE`), and silent failures.

Every wait must be an **RPC completion**, an **explicit event signal**, or a **lifecycle death subscription**.

---

## 1. Core Operating Principles

| Dimension | Broken Pattern (Anti-Pattern) | Robust Pattern (Event-Driven) |
| :--- | :--- | :--- |
| **CLI Observation** | `frida ... \| head -40` (Pipe buffer drop, `SIGPIPE` hang) | Host Python runner with structured `send()` filtering |
| **Readiness Wait** | `sleep 3` after spawn/attach | Host waits on `threading.Event` triggered by agent's `ready` message |
| **Output Buffering** | Piping Python stdout (`\| grep ...`) | Streamed logging via `sys.stderr.flush()` or `device.on('output')` |
| **State Polling** | `while (!found) { sleep(0.5); }` | Push-based edge triggers or `Process.attachModuleObserver` |
| **Hook Teardown** | Abrupt CLI `kill` / `timeout 60` | Graceful RPC completion signal followed by `script.unload()` |

---

## 2. Standard Host Runner Template

```python
import sys, threading, frida

def run_session(target_spec, agent_code, is_spawn=False, timeout=15.0):
    ready_evt = threading.Event()
    done_evt = threading.Event()
    results = []

    def on_message(msg, data):
        if msg["type"] == "send":
            p = msg.get("payload", {})
            tag = p.get("tag") or p.get("t")
            if tag == "ready": ready_evt.set()
            elif tag == "done": results.append(p.get("data")); done_evt.set()
            elif tag == "log": print(f"[*] {p.get('msg', p)}", file=sys.stderr, flush=True)
        elif msg["type"] == "error":
            print(f"[!] Agent error: {msg.get('stack', msg.get('description'))}", file=sys.stderr)
            ready_evt.set(); done_evt.set()

    device = frida.get_usb_device(timeout=5) if "--usb" in sys.argv else frida.get_local_device()
    device.on("process-crashed", lambda pid, crash: print(f"[CRASH] PID {pid}: {crash.report}", file=sys.stderr))
    
    if is_spawn:
        pid = device.spawn([target_spec], stdio="pipe")
        session = device.attach(pid)
    else:
        pid = None
        session = device.attach(target_spec)

    session.on("detached", lambda reason, crash: print(f"[*] Detached ({reason})", file=sys.stderr))
    script = session.create_script(agent_code)
    script.on("message", on_message)
    script.load()

    if is_spawn:
        device.resume(pid)

    if not ready_evt.wait(timeout=5.0):
        session.detach()
        raise TimeoutError("Agent failed to report readiness.")

    return session, script, done_evt, results
```

---

## 3. Quick-Start & Tested Invocations

Use [scripts/probe.py](./scripts/probe.py) for attach-or-spawn operations with zero hard sleeps:

```bash
# Attach to running app and run basic healthcheck RPC
python3 scripts/probe.py --target MyApp --rpc info

# Query loaded modules with limit
python3 scripts/probe.py --target MyApp --rpc modules --limit 5

# Spawn binary under server context, stream stdio, and wait for clean exit
python3 scripts/probe.py --spawn /path/to/bin --argv arg1 arg2 --rpc info --wait-exit

# Bridge-free ObjC introspection: find which classes implement a selector
python3 scripts/probe.py --target MyApp --agent agents/objc_scan.js \
    --rpc implementors --rpc-args '["initWithClientLocation:coarseMetaData:"]'

# Triage iOS crash report (.ips) to image + offset + symbol
python3 scripts/crash_map.py /path/to/report.ips --json
```

---

## 4. Frida 17+ Modern Runtime Essentials

* **Decoupled Bridges**: `frida-objc-bridge`, `frida-java-bridge`, and `frida-swift-bridge` are no longer bundled in `create_script()` contexts (`typeof ObjC === "undefined"`).
* **Compiling Bridges on the Fly**: Use TypeScript + ESM imports bundled via `frida.Compiler()` (automatically handled by `scripts/probe.py` for `.ts` files).
* **Bridge-Free Native Calls**: Use direct C runtime exports via `NativeFunction` for zero-overhead introspection without bridge dependencies (see [agents/objc_scan.js](./agents/objc_scan.js)).
* **Type Signatures vs. Selector Names**: Never message an unknown ObjC selector blindly. An integer/boolean return messaged as an object causes low-address crashes (`0x1`, `0x2`) in `objc_retain`. Read the type encoding first with `method_getTypeEncoding`.

---

## 5. Anti-Tamper & Integrity Decision Matrix

| Symptom | Probable Cause | Correct Remediation | Reference |
| :--- | :--- | :--- | :--- |
| **App exits ~1s after hook** (Exit 0 / no crash log) | `__TEXT` integrity / memory hash check detects inline opcode rewrite | Use **IMP Swizzling** or VMT hooking (replace function pointer, not code bytes) | [ios-swizzle.md](./references/ios-swizzle.md) |
| **Crash with `SIGBUS` / `KERN_PROTECTION_FAILURE`** | Code-signing page invalidation triggered by memory write | Do not modify code pages in place; patch on disk & re-sign, or swizzle pointer | [ios-gotchas.md](./references/ios-gotchas.md) |
| **App hangs indefinitely** (stuck on splash/sheet) | Hooked gated callback without firing completion/failure contract | Simulate the app's own failure delegate (`adFailedWithError`) instead of no-op | [bypass-strategy.md](./references/bypass-strategy.md) |
| **Hook never fires**, app runs normally | Inlined function or too short for 16-byte trampoline | Hook caller frame, xref predecessor, or monitor higher-level dispatcher | [patterns.md](./references/patterns.md) |

---

## 6. Progressive Reference Library

Consult specialized guides for in-depth recipes:

* [references/frida17.md](./references/frida17.md) — 17.x breaking changes, bridge unbundling, ESM compiler, modern exports lookup.
* [references/patterns.md](./references/patterns.md) — Complete catalogue of event-driven recipes (module observers, firstCall, death subscriptions).
* [references/ios-objc.md](./references/ios-objc.md) — Bridge-free Objective-C introspection, class scans, type encodings, heap traps (`chooseSync`).
* [references/ios-swizzle.md](./references/ios-swizzle.md) — IMP swizzling vs Interceptor when `__TEXT` is hashed; callback lifetime & retain discipline.
* [references/ios-storekit.md](./references/ios-storekit.md) — StoreKit 1/2 probing, catalogue dumps, and payment sink rewriting (`agents/storekit.ts`).
* [references/bypass-strategy.md](./references/bypass-strategy.md) — Defensive bypass strategies: failure-path simulation, MITM key pinning, state machines.
* [references/crash-forensics.md](./references/crash-forensics.md) — iOS `.ips` anatomy and signal-to-cause triage table.
* [references/ios-gotchas.md](./references/ios-gotchas.md) — Rootless tunnels, launchd daemon management, spawn vs uiopen, and anti-debug traps.
