# iOS / Objective-C without the bridge (Frida 17)

Since 17.0.0 the ObjC bridge is not bundled, so `create_script()` agents must either
bundle `frida-objc-bridge` or call the runtime directly. These are the direct-call
recipes, distilled from a real reverse-engineering session on a jailed iPhone.

## Resolve symbols (the 17.x way)

`Module.getExportByName` is gone. `Module.findGlobalExportByName` searches all modules;
`Module.getGlobalExportByName` throws when missing. A tolerant helper:

```js
function sym(name) {
  try { if (Module.getGlobalExportByName) return Module.getGlobalExportByName(name); } catch (e) {}
  try { return Module.findGlobalExportByName(name); } catch (e) {}
  const m = /^(.+)!(.+)$/.exec(name);
  if (m) return Module.findExportByName(m[1], m[2]);
  return null;
}
```

## Who implements a selector (whole-class-list scan)

Cheap and decisive: instead of guessing class names, ask the runtime which classes
implement a selector. Scanning ~10^5 classes takes milliseconds.

```js
const objc_getClassList   = new NativeFunction(sym("objc_getClassList"), "int", ["pointer", "int"]);
const class_getName       = new NativeFunction(sym("class_getName"), "pointer", ["pointer"]);
const class_getInstanceMethod = new NativeFunction(sym("class_getInstanceMethod"), "pointer", ["pointer", "pointer"]);
const sel_registerName    = new NativeFunction(sym("sel_registerName"), "pointer", ["pointer"]);

function classesImplementing(selName) {
  const want = sel_registerName(Memory.allocUtf8String(selName));
  const n = objc_getClassList(ptr(0), 0);
  const buf = Memory.alloc(n * Process.pointerSize);
  const got = objc_getClassList(buf, n);
  const hits = [];
  for (let i = 0; i < got; i++) {
    const cls = buf.add(i * Process.pointerSize).readPointer();
    if (cls.isNull()) continue;
    if (!class_getInstanceMethod(cls, want).isNull()) hits.push(class_getName(cls).readUtf8String());
  }
  return hits;                       // e.g. ["BaseMsgContentLogicController"]
}
```

`agents/objc_scan.js` exposes exactly this through `rpc.exports`.

## Type encodings beat selector names

A selector's name is a guess; `method_getTypeEncoding` is the ABI. Before mass-calling
getters, read the return type — otherwise an integer return gets retained as an object
and the process dies at a fault address that *is* the integer.

```js
const method_getTypeEncoding = new NativeFunction(sym("method_getTypeEncoding"), "pointer", ["pointer"]);
// returns e.g. "@32@0:8@16@24"  => id, then two object args
//          "I16@0:8"           => uint32 return!
```

Rules:

- only `@` (and `#`, `:` which are object-ish) may be received as `id`;
- `I/i/S/s/Q/q/B/c/C` must be read as integers, `d/f` as doubles;
- passing a wrong-typed value into ObjC and then messaging it is the #1 way these
  sessions crash the target (look for a crash address that is suspiciously small and
  odd, e.g. `0x2`, `0x5f00a1b2` — that is a value being `objc_retain`ed).

## Calling methods

```js
const objc_msgSend_id = new NativeFunction(sym("objc_msgSend"), "pointer",
                                            ["pointer","pointer","pointer","pointer"]); // up to 2 args
```

Use raw `objc_msgSend` for methods the bridge cannot see — **forwarding** (`forwardInvocation:`,
`resolveInstanceMethod:`) is invisible to method-table lookups, so a "no such selector"
answer from the bridge is often wrong:

```js
const wrap = objc_msgSend_id(ctrl, sel_registerName(Memory.allocUtf8String("formImageMsgByMMAsset:toUserName:")), asset, user);
```

## Instance access: prefer `alloc`/`init` over heap scanning

- `ObjC.chooseSync(...)` scans the entire heap and returns objects **without retaining
  them**; using one a moment later is a use-after-free (`EXC_BAD_ACCESS / SIGBUS`,
  `codes 0x2`). If you must, `objc_retain` immediately and keep it short-lived.
- Many "logic controller" classes are constructible offline — `[[cls alloc] init]` —
  which turns a UI-bound API into a pure computation. Try that before hunting for a
  live instance.
- When you do need an existing instance, get it from a delegate/singleton selector
  (`sharedInstance`, `activeUserContext`, …) rather than scanning.

## `hasSel` pitfalls

```js
// WRONG: a missing property is undefined, and undefined !== null
return cls["- " + sel] !== null;
// RIGHT
const m = class_getInstanceMethod(clsPtr, selPtr);
return !!m && !m.isNull();
```

## Other traps

- `Interceptor.attach` failing with *"unable to intercept function at 0x…; please file a
  bug"* means the function is too short / unaligned for inline hooking. **It does not mean
  the function is never called.** Use a caller hook, a breakpoint-style probe on a
  neighbouring symbol, or static analysis.
- `session.enumerate_threads()` can throw on iOS; judge liveness from
  `device.enumerate_processes()` instead.
- Attaching to a **suspended background** app fails with
  `unexpected error while resuming process: (os/kern) failure`. Bring it forward
  (`uiopen -b <bundleid>`) first.
