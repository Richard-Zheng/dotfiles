---
name: frida-operation
description: Operate Frida 17 from Python agents on iOS/Android/macOS — event-driven (no hard sleeps), rpc.exports for synchronization, spawn/attach recipes, stdio capture, module observers, memory patching that survives code signing, and the Frida 17 bridge split (ObjC/Java/Swift no longer bundled). Use whenever writing or debugging Frida host scripts, frida-server tunnels, spawn-gating, or hooking with Frida.
---

# Operating Frida 17 (Python host + JS agent)

The hard part of Frida work is never the hook — it is **waiting**. Most scripts rot
because they `time.sleep(2)` and hope. This skill is about the opposite: every wait
is an event or an RPC call.

Read `references/frida17.md` before writing a new agent (breaking changes in 17.x,
and the "ObjC is undefined" trap). Read `references/patterns.md` for the recipes.
`scripts/probe.py` + `agents/probe.js` are a working starting point.

## Rule zero: distrust your own observation

"Nothing printed" is not "nothing happened". Before concluding a hook failed, prove the
process is alive, the session is alive, and the script reached that line.

| Bad | Symptom | Good |
| --- | --- | --- |
| `timeout 60 frida ... \| head -40` | timeout kills it, the pipe buffer is discarded, the screen shows half a log and looks "stuck" | `setsid nohup <cmd> > /tmp/x.log 2>&1 < /dev/null &` then `sleep N; cat /tmp/x.log` |
| `python3 script.py \| grep ...` | block buffering hides everything | `python3 -u`, and write to a log file |
| `frida -p PID -l s.js -q < /dev/null` | with stdin not a TTY, frida >= 17 loads the script and exits, so `setTimeout`/async work never runs | drive it from the Python bindings and keep the session alive |

Load a script, then **make one RPC call**: the round-trip proves the agent survived
evaluation. A top-level `send()` can be delivered after `load()` returns, and a failed
`rpc.exports` assignment shows up only as an `error` message — check `script.on("message")`.

## The three rules

1. **No `sleep`.** `Script.load()` is synchronous. Anything you would sleep-wait for is
   either (a) already done when `load()` returns, (b) an RPC you can call, or (c) an
   event you can subscribe to with a bounded timeout.
2. **Synchronize with `rpc.exports`, not with timing.** The agent exposes functions
   returning values or Promises; the host calls `script.exports_sync.fn()` (blocking,
   returns the Python value) or `await script.exports.fn()` with `frida.aio`.
3. **Subscribe to death.** `session.on("detached", reason)`, `device.on("process-crashed")`,
   `script.on("destroyed")`. A crashed target must wake you up immediately, not after a timeout.

## Host: pick sync or async, never both

```python
# sync — fine for scripts, CI, one-shot probes
import frida
dev = frida.get_device_manager().add_remote_device("127.0.0.1:27042")
sess = dev.attach("MyApp")                      # attach by name, no polling
script = sess.create_script(open("agent.js").read())
script.on("message", lambda m, data: print(m.get("payload") or m.get("description")))
script.load()                                   # synchronous: hooks are live here
print(script.exports_sync.info())               # blocking RPC, returns dict
```

```python
# async — frida.aio mirrors the whole API with await
import asyncio, frida.aio
async def main():
    dev = await frida.aio.get_remote_device("127.0.0.1:27042")
    pid = await dev.spawn(["prog", "arg"], stdio="pipe")
    sess = await dev.attach(pid)
    script = await sess.create_script(src)
    await script.load()
    await dev.resume(pid)
    print(await script.exports.info())
asyncio.run(main())
```

## Bounded waits (the only acceptable "wait")

```python
done = threading.Event()                        # sync host
script.on("message", lambda m, d: done.set() if m.get("payload", {}).get("tag") == "ready" else None)
script.load()
assert done.wait(10), "agent never reported ready"
```

Agent side, when the thing you wait for is "some module gets loaded":

```js
rpc.exports.waitModule = (name, timeoutMs = 5000) => new Promise((resolve, reject) => {
  const found = () => Process.findModuleByName(name);
  if (found()) return resolve(found());
  const obs = Process.attachModuleObserver({
    onAdded(m) { if (m.name === name) { obs.detach(); resolve(m); } }
  });
  setTimeout(() => { obs.detach(); reject(new Error(`timeout: ${name}`)); }, timeoutMs);
});
```

## Spawn, args, stdio — one call

`Device.spawn(program, argv=[...], envp={...}, cwd=..., stdio="pipe")` takes argv
directly; do not pass a list as `program`. `stdio="pipe"` + `device.on("output")`
captures the child's stdout/stderr without redirecting files.

## attach vs spawn: they are not interchangeable

| Mode | Reality |
| --- | --- |
| `attach` | Works on a **foreground** process. Attaching to a suspended background app fails with `unexpected error while resuming process: (os/kern) failure` — bring it forward first (`uiopen -b <bundleid>`, `open -a`, ...). |
| `spawn` | Fails on **encrypted App Store apps**: they hit `brk` inside `dyld4::RuntimeState::notifyObjCInit` (EXC_BREAKPOINT/SIGILL). It is not anti-debug — don't waste hours there. Jailbreak-built binaries spawn fine. |

Process names are often **localized** (`微信`, not `com.tencent.xin`), and
`device.get_process("com.tencent.xin")` raises `ProcessNotFoundError` because it matches
the *process name*. Resolve by name → substring over `enumerate_processes()` →
`enumerate_applications()` (bundle id or localized name), in that order.

## iOS: things that bite

- Rootless jailbreak: server at `127.0.0.1:27042` inside the device; tunnel with
  `ssh -N -L 127.0.0.1:27042:127.0.0.1:27042 user@device`, then `add_remote_device`.
  The server binds loopback only, so the tunnel dies with every reboot/network blip —
  rebuild it conditionally: `ss -ltn | grep -q 127.0.0.1:27042 || ssh -N -f ... -L 27042:...`.
- **One server only.** A launchd-managed `frida-server` plus a manually started
  `-l 0.0.0.0:27042` copy produces `unexpected error while resuming process` /
  `timeout was reached`. `killall frida-server` is a safe reset when launchd keeps it alive.
- Client and server versions should match (`frida --version` vs
  `frida-server --version`). Mismatch symptoms look like protocol/transport errors that
  masquerade as target bugs.
- `spawn` launches through the server's user (root if frida-server runs as root),
  `uiopen --bundleid` launches through launchd (the app's normal user). Some targets only
  work in one of the two — if a binary dies instantly under `spawn` but the GUI app
  works, the difference is launch context, not your hook.
- **Exactly one session per app.** A second session attaching while the first is attached
  makes `create_script` time out, and hooks that reported success never fire. Kill the old
  session first.
- **`-f` evaluates the agent before `main`.** Touching Foundation there (`NSHomeDirectory`,
  building `NSString`s) can crash the process; defer, and do UI work on the main queue.
- **Never patch `__TEXT` in place at runtime.** On a signed app, making a code page
  writable and editing it invalidates the page: later execution faults with
  `SIGBUS KERN_PROTECTION_FAILURE` or `SIGILL` at a bogus PC. Patch a copy on disk
  (`dd`/Python) and re-sign (`ldid -S ent.plist`). `Memory.patchCode` is the least-bad
  in-process option (it does the mprotect dance) but still writes to a signed page, so it
  does not make the page legal — prefer **IMP swizzle**, which writes no code bytes at all.
  Symptom to recognise: crash PC like `0xffffffffffffffff`, or the *next* call into an
  already-patched function faulting.
- Anti-debug is common and *is not your hook's fault*: `sysctl` `KERN_PROC_PID` +
  `P_TRACED (0x800)` at `kinfo_proc + 0x21 bit 3`, `ptrace(PT_DENY_ATTACH)`,
  `sysctl` via `dlsym`. Check these before blaming Frida.

## Frida 17: no more bundled bridges

Plain `create_script()` agents have **no `ObjC`, `Java` or `Swift`** (`typeof ObjC === "undefined"`).
Three ways to get them:

1. `frida`/`frida-trace` REPL — bridges are baked in (`frida-tools >= 14.0.0`).
2. `frida-compile` + `import ObjC from "frida-objc-bridge"` (see `references/frida17.md`).
3. Python `frida.Compiler()` — compile a TS agent from the host, then `create_script(compiled)`.

If you only need a couple of runtime calls, skip the bridge: resolve
`objc_getClass` / `sel_registerName` / `objc_msgSend` with `NativeFunction` and call them.

## When the app defends itself

Two different defences need two different answers — pick the right one before writing code:

| Symptom | Defence | Answer |
| --- | --- | --- |
| Hook installs, app exits a second later | `__TEXT` integrity hash | **IMP swizzle** — swap `Method.implementation`, never code bytes (`references/ios-swizzle.md`) |
| Patching a code page works, then the *next* call into that page faults | code-signing page invalidation | same thing: stop patching bytes; or patch on disk and re-sign |
| Hook never fires, no crash | the function is too short to inline-hook | static analysis, or hook a caller/neighbouring symbol |
| Everything legal but the feature still refuses | a state machine, not a value check | take the error string into IDA and gate the transition (`references/bypass-strategy.md`) |
| Blocked feature "hangs" instead of skipping | you no-op'd a call the app awaits | call the app's own failure/close callback instead |

Also in `references/bypass-strategy.md`: pin the crypto key instead of reimplementing the
scheme (so a MITM proxy can read plaintext), match response envelopes by structure not by
keywords, and why private APIs can run-but-do-nothing without entitlements.

## Crash forensics

`scripts/crash_map.py` turns an Apple `.ips` into "fault address → image+offset → stack":

```sh
python scripts/crash_map.py /var/mobile/Library/Logs/CrashReporter/App-*.ips
# signal : EXC_BAD_ACCESS / SIGBUS KERN_PROTECTION_FAILURE  Bus error: 10
# fault  : 0x1025513d4 -> SimLoc+0x93d4
#   #0  SimLoc +0x0093d4
```

Signal → cause cheat sheet (see `references/crash-forensics.md`):

| Signal | Typical cause |
| --- | --- |
| `EXC_BREAKPOINT / SIGILL` in `dyld notifyObjCInit` | spawn-injecting an encrypted app |
| `EXC_BAD_ACCESS / SIGBUS (codes 0x2)` | dangling pointer, e.g. objects from a heap scan that were never retained |
| `EXC_BREAKPOINT / SIGTRAP` in `_dispatch_once_wait` | recursive `dispatch_once` deadlock |
| `SIGSEGV` at a tiny/odd address | an integer or handle messaged as an object |
| `SIGBUS KERN_PROTECTION_FAILURE` in `__TEXT` | a code page of a signed binary was modified |

## Division of labour

Frida is for **asking questions**; IDA is for **reading the answer**; a tweak is for
**landing it**. A good loop: enumerate the runtime (class list scans, type encodings,
cheap and decisive) → read the implementation statically → implement in a tweak and
verify once. A long-lived result belongs in a dylib, not in an attach session.

## Files

- `scripts/probe.py` — attach-or-spawn probe: loads an agent, calls an RPC, prints JSON,
  exits on detach; zero sleeps.
- `agents/probe.js` — agent template with `rpc.exports` (info, modules, threads),
  `waitModule`, and an exception handler that reports crashes before dying.
- `agents/objc_scan.js` — bridge-free ObjC introspection: `implementors` (class + IMP +
  superclass chain, so inherited methods and selector-name collisions are distinguishable),
  `classesImplementing`, `typeEncoding`, `encodings`, `respondsTo`.
- `scripts/crash_map.py` — `.ips` → image+offset+stack.
- `references/frida17.md` — 17.x breaking changes, bridge wiring, version pairing.
- `references/patterns.md` — catalogue of no-sleep recipes (RPC, events, observers,
  patchCode, spawn gating, message routing, error surfaces).
- `references/ios-objc.md` — calling the ObjC runtime directly: class-list scans, type
  encodings vs selector names, forwarding methods, `chooseSync` hazards.
- `references/ios-swizzle.md` — IMP swizzle vs `Interceptor` when `__TEXT` is hashed;
  callback lifetime, retain discipline, `objc_msgSend` fallback.
- `references/ios-ui-automation.md` — drive the UI through the view tree (no touch
  injection), control events, struct-return arrays, in-app screenshots.
- `references/bypass-strategy.md` — failure-path simulation, key pinning for MITM,
  envelope matching, state-machine gates, entitlements.
- `references/crash-forensics.md` — `.ips` anatomy and the signal→cause table.

## Tested invocations

Verified end-to-end against a rootless iOS 16 device (client 17.23.3, server 17.22.2,
server tunneled to `127.0.0.1:27042`):

```sh
# attach to a running app, one RPC, no sleeps anywhere
python scripts/probe.py --target SimLoc --rpc info

# pull a slice of state
python scripts/probe.py --target SimLoc --rpc modules --limit 3

# spawn a binary as the server's user, capture its stdio, wait for exit
python scripts/probe.py --spawn /var/jb/usr/bin/uname --argv=-a --rpc info --wait-exit

# bridge-free ObjC introspection: who really implements a selector
python scripts/probe.py --target SimLoc --agent agents/objc_scan.js \
    --rpc implementors --rpc-args '["initWithClientLocation:coarseMetaData:"]'
#   CLLocation      imp=0x1b394f94c  chain=[CLLocation, NSObject]
#   MNLocation      imp=0x1b394f94c  chain=[MNLocation, CLLocation, NSObject]   <- inherited
#   UIKeyboardCandidateViewStyle imp=0x1aab47e4c chain=[..., NSObject]         <- name collision
```

Quirks worth remembering:

- dash-prefixed program arguments need `--argv=-a` (argparse would read `-a` as a flag);
- `detached` reason distinguishes outcomes: `process-terminated` = clean exit,
  `process-replaced` = `execve`, and a real crash also arrives via
  `device.on("process-crashed")` with a `crash.report`;
- stdio events must be *streamed* (print inside the handler). Buffering them and
  printing after `detached` loses the tail — that race is the classic "no output" bug.
