# Frida 17.x notes (verified against the installed toolchain)

Installed here: **frida (Python) 17.23.3**, device `frida-server` 17.22.2,
`frida-tools` 14.x. Python package path: `/usr/lib/python3.14/site-packages/frida/`
(`__init__.py` = sync API, `aio.py` = asyncio API, `_frida.pyi` = low-level stubs).

## Breaking changes in 17.0.0

Source: <https://frida.re/news/2025/05/17/frida-17-0-0-released/>,
<https://frida.re/docs/bridges/>

1. **Runtime bridges are no longer bundled with GumJS.** `frida-objc-bridge`,
   `frida-java-bridge`, `frida-swift-bridge` are separate ESM packages consumed with
   `frida-compile`. Consequence: an agent loaded through `create_script()` has
   `typeof ObjC === "undefined"`. The `frida` REPL and `frida-trace` do bundle all three
   (frida-tools >= 14.0.0) so old copy-paste snippets still work there — that is why
   "it works in the REPL but not from my Python script".
2. **Legacy enumeration APIs removed**: `Process.enumerateModules({ onMatch, onComplete })`,
   `Process.enumerateThreads(...)` callbacks. Use the array-returning form:
   `for (const m of Process.enumerateModules()) ...`.
3. **Legacy memory accessors removed**: `Memory.readU32(p)` / `Memory.writeU32(p, v)`.
   Use methods on `NativePointer`: `p.readU32()`, `p.writeU32(v)` (writes return the
   pointer, so they chain).

### What the JS runtime actually exposes (measured on server 17.22.2)

```
Module.findExportByName       -> undefined      (removed; use the two below)
Module.getExportByName        -> undefined
Module.findGlobalExportByName -> function
Module.getGlobalExportByName  -> function
Memory.readU32                -> undefined      (use ptr.readU32())
ObjC                          -> undefined      (bridge not bundled)
Process.enumerateModules()    -> array
```

So `sym()`/`findSymbol()` helpers must not call `findExportByName` at all; if you need a
module-scoped lookup, call `Module.findExportByName` only after feature-detecting it,
otherwise use `findGlobalExportByName`.

Also seen on 17.x: `v.respondsToSelector_('text')` can return `false` for views that do
respond, so guarding on it silently yields `null`. Use `try { v.text() } catch {}`.

## Getting a bridge into a `create_script()` agent

Option A — compile with the CLI (needs node/npm once):

```sh
frida-create -t agent          # scaffolding in cwd
npm install frida-objc-bridge
# agent.ts
#   import ObjC from "frida-objc-bridge";
#   console.log(ObjC.available);
frida-compile agent.ts -o _agent.js -S -c
```

Option B — compile from Python, same result, no shell:

```python
import frida
compiler = frida.Compiler()
compiler.on("diagnostics", lambda d: print("diag", d))
compiled = compiler.build("agent.ts")       # returns the JS bundle as str
script = session.create_script(compiled)
```

Option C — no bridge at all (often enough):

```js
const objc_getClass   = new NativeFunction(Module.getGlobalExportByName("objc_getClass"), "pointer", ["pointer"]);
const sel_registerName = new NativeFunction(Module.getGlobalExportByName("sel_registerName"), "pointer", ["pointer"]);
const objc_msgSend    = new NativeFunction(Module.getGlobalExportByName("objc_msgSend"), "pointer", ["pointer","pointer"]);
const NSString = objc_getClass(Memory.allocUtf8String("NSString"));
const sel = sel_registerName(Memory.allocUtf8String("stringWithUTF8String:"));
const s = objc_msgSend(NSString, sel, Memory.allocUtf8String("hi"));
```

(Keep `Memory.allocUtf8String` results alive for as long as the callee may use them —
see "String allocation" in <https://frida.re/docs/best-practices/>.)

## Python API surface worth knowing (names verified in `frida/__init__.py`)

```python
Device.spawn(program, argv=None, envp=None, env=None, cwd=None, stdio=None, **aux)  # :626
Device.resume(target); Device.kill(target); Device.attach(target)
Device.enable_spawn_gating(); Device.disable_spawn_gating()
Device.on("output" | "spawn-added" | "spawn-removed" | "child-added" | "child-removed"
          | "process-crashed" | "uninjected" | "lost")                             # :546-561
DeviceManager.add_remote_device(addr)                                               # tunneled server
Session.on("detached", cb)          # cb(reason, crash) ; reason: application-requested,
                                    # process-replaced, process-terminated, connection-terminated, device-lost
Session.create_script(source, name=None, snapshot=None, runtime=None)
Script.load()                       # synchronous; hooks are installed when it returns
Script.on("message" | "destroyed")
Script.exports_sync.<fn>(...)       # blocking RPC -> Python value                    # :1707
Script.list_exports_sync()                                                          # :1752
Script.post(obj) / script-side recv()
```

`frida/aio.py` mirrors everything with `async`/`await` (`await dev.spawn(...)`,
`await script.load()`, `await script.exports.fn()`), so no threads and no sleeps.

## JS API verified present in the 17.x typings (@types/frida-gum)

`Process.attachModuleObserver({onAdded,onRemoved,onLoad?,...})`, `Module.ensureInitialized`,
`Process.setExceptionHandler`, `Process.runOnThread`, `Process.attachThreadObserver`,
`Memory.patchCode`, `Memory.scanSync`, `Process.enumerateRanges`, `Thread.backtrace`,
`Interceptor.attach/replace/revert`, `NativeCallback`/`NativeFunction`, `setTimeout/setInterval`.

## Version pairing pitfalls

- Client newer than server is usually fine; the reverse is not. `frida --version` and
  `frida-ps -U` are the quick health check through the tunnel.
- On iOS rootless, restart the server with
  `sudo launchctl kickstart -k system/re.frida.server` instead of killing it manually.
