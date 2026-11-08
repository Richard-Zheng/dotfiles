# Frida 17.x Technical Reference & Migration Guide

Frida 17.0.0 represents a major architectural overhaul focused on **decoupling runtime bridges from GumJS, reducing footprint, and enforcing modern, asynchronous, and modular JavaScript/TypeScript APIs**.

Authoritative references:
- Release Notes: https://frida.re/news/2025/05/17/frida-17-0-0-released/
- Runtime Bridges: https://frida.re/docs/bridges/

---

## 1. Core Breaking Changes: Unbundled Language Bridges

Prior to Frida 17, `frida-objc-bridge`, `frida-java-bridge`, and `frida-swift-bridge` were statically embedded into the GumJS runtime.

- **Current State**: Starting with 17.0.0, all language bridges are completely decoupled from GumJS and published as standalone ESM (ECMAScript Modules) packages on npm.
- **Scope & Symptoms**:
  - **`session.create_script()` (Python/C/Node.js host)**: When loading plain JS scripts, runtime globals are unpopulated: `typeof ObjC === "undefined"`, `typeof Java === "undefined"`, `typeof Swift === "undefined"`.
  - **CLI REPL (`frida`) & `frida-trace`**: To preserve backward compatibility and interactive ad-hoc usage, `frida-tools >= 14.0.0` **bundles all three bridges**. This is why bridge snippets work seamlessly in the interactive REPL but fail with `ReferenceError: ObjC is not defined` when executed via host Python scripts.

Bridge Integration Strategies:

### Option A: Just-In-Time Compilation with `frida.Compiler` (Recommended)

Frida's Python bindings expose `frida.Compiler`, which bundles TypeScript and standard ESM `import` statements on the fly in memory without external build steps:

```python
import frida

compiler = frida.Compiler()
compiler.on("diagnostics", lambda diag: print(f"[Compiler] {diag}"))

# agent.ts can directly use `import ObjC from "frida-objc-bridge"`
bundle_code = compiler.build("agent.ts")

script = session.create_script(bundle_code)
script.load()
```

### Option B: Pre-compilation via `frida-compile` CLI

Use npm to install required bridges as dependencies and produce a self-contained bundle:

```bash
npm init -y
npm install --save-dev frida-compile @types/frida-gum
npm install frida-objc-bridge frida-java-bridge

# agent.ts:
# import ObjC from "frida-objc-bridge";
# import Java from "frida-java-bridge";

npx frida-compile agent.ts -o dist_agent.js -S -c
```

### Option C: Bridge-Free Native Invocations (Zero Overhead)

For lightweight probing, hooking, or inspecting specific selectors, bypass bridges entirely by making raw C runtime calls:

```javascript
function sym(name) {
  try { return Module.getGlobalExportByName(name); } catch (e) {}
  return null;
}

const objc_getClass = new NativeFunction(sym("objc_getClass"), "pointer", ["pointer"]);
const sel_registerName = new NativeFunction(sym("sel_registerName"), "pointer", ["pointer"]);
const objc_msgSend = new NativeFunction(sym("objc_msgSend"), "pointer", ["pointer", "pointer"]);

const NSString = objc_getClass(Memory.allocUtf8String("NSString"));
const sel = sel_registerName(Memory.allocUtf8String("stringWithUTF8String:"));
const res = objc_msgSend(NSString, sel, Memory.allocUtf8String("hello, frida 17"));
```

---

## 2. Runtime API Deprecations & Modern Replacements

### 2.1 Deprecation of Legacy `Module` Lookup APIs

Global and legacy static export resolution methods have been restructured or removed:

- ❌ `Module.findExportByName(mod, sym)` (Deprecated / strict argument requirements)
- ❌ `Module.getExportByName(mod, sym)` (Removed)
- ❌ `Module.findSymbolByName` / `Module.getSymbolByName` (Removed)
- ❌ `Module.findBaseAddress` / `Module.getBaseAddress` (Removed)
- ❌ `Module.ensureInitialized` (Removed)

**Modern Replacements**:

1. **Global Export Lookup** (Recommended for cross-module symbols):

```javascript
Module.findGlobalExportByName("open");
Module.getGlobalExportByName("open"); // Throws a JS exception if not found
```

2. **Module Instance Lookup** (Fastest; avoids repeated global namespace scans):

```javascript
const libc = Process.getModuleByName("libc.so"); // or Process.findModuleByName(...)
const openPtr = libc.getExportByName("open");
const base = libc.base;
```

### 2.2 Removal of Callback-Based Enumeration APIs

APIs accepting legacy `{ onMatch, onComplete }` callback objects have been removed in favor of direct array returns:

```javascript
// ❌ Legacy syntax (Removed)
Process.enumerateModules({
  onMatch: function(mod) { ... },
  onComplete: function() { ... }
});

// ✅ Modern 17.x syntax
for (const mod of Process.enumerateModules()) {
  // Access mod.name, mod.base, etc.
}
```

### 2.3 Native Pointer Accessors

* ❌ `Memory.readU32(p)` and `Memory.writeU32(p, val)` are removed.
* ✅ Use instance methods directly on `NativePointer` (write operations support chaining):
```javascript
const val = p.readU32();
p.writeU32(0x1337).add(4).writeU32(0xdeadbeef);
```

---

## 3. Python API surface worth knowing

Frida provides synchronized (`frida.*`) and asynchronous (`frida.aio.*`) APIs. Do not mix both paradigms within the same runner.

### 3.1 Synchronous API Surface

* `Device.spawn(program, argv=None, envp=None, cwd=None, stdio="pipe")`
* `Device.resume(target)` / `Device.kill(target)` / `Device.attach(target)`
* `Device.on("output" | "spawn-added" | "spawn-removed" | "child-added" | "child-removed" | "process-crashed" | "uninjected" | "lost", handler)`
* `DeviceManager.add_remote_device(addr)`
* `Session.create_script(source, name=None, snapshot=None, runtime=None)`
* `Session.on("detached", handler)`: `handler(reason, crash)`
* `Script.load()`: Synchronous; blocks until top-level agent execution completes.
* `Script.exports_sync.<method>(*args)`: Blocking RPC call returning native Python objects.
* `Script.list_exports_sync()`
* `Script.on("message" | "destroyed", handler)`

### 3.2 Asynchronous API (`frida.aio`)

For concurrent tasks, UI-driven tools, or streaming environments, prefer `asyncio`:

```python
import asyncio
import frida.aio

async def main():
    dev = await frida.aio.get_usb_device()
    pid = await dev.spawn(["/bin/ls", "-la"], stdio="pipe")
    sess = await dev.attach(pid)
    
    script = await sess.create_script("rpc.exports = { ping() { return 'pong'; } };")
    await script.load()
    await dev.resume(pid)
    
    res = await script.exports.ping()
    print("RPC Result:", res)
    await sess.detach()

asyncio.run(main())
```

---

## 4. Key Troubleshooting & Environmental Pitfalls

1. **Version Parity**:
* Host `frida` (Python package/CLI) and target `frida-server` must share the same major version. Mismatched majors (e.g., 16.x client talking to 17.x server) frequently manifest as unexpected `ProtocolError` or `TransactionError`.

2. **Rootless iOS Server Lifecycle**:
* Do not manually `killall frida-server` on rootless iOS environments to prevent port collision or degraded privilege states. Kickstart the launchd daemon cleanly:
```bash
sudo launchctl kickstart -k system/re.frida.server
```

3. **Early Spawn (`-f`) Execution Window**:
* When spawning (`-f`), scripts execute during dynamic loader initialization (`_start` / `dyld`) before `main()`. Accessing higher-level runtime environments (e.g., querying Foundation paths or calling initialized singletons) too early can cause targets to terminate immediately. Defer early initialization using `Process.attachModuleObserver` or thread-dispatch queues.
