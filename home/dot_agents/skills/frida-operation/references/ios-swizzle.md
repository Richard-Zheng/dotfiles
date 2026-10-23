# Bypassing `__TEXT` integrity checks: IMP swizzle instead of `Interceptor`

Some apps hash their own `__TEXT`. `Interceptor.attach` rewrites the first bytes of the
function (inline hook) → the hash changes → the app kills itself. The symptom is
"the hook installs, then the app exits a second later", often with no crash log.

The fix is to never touch code bytes: swap the method **implementation pointer**.

```js
// Requires the ObjC bridge (REPL / frida-compile), or ObjC.api from a bundled bridge.
const keepAlive = [];                      // callbacks are GC'd if you don't hold them

function swizzle(cls, sel, body) {
  const mm = ObjC.classes[cls][sel];       // { handle: Method*, implementation, returnType, argumentTypes, types }
  if (!mm) throw new Error(`no method ${cls} ${sel}`);
  const origFn = new NativeFunction(mm.implementation, mm.returnType, mm.argumentTypes);
  const cb = new NativeCallback(function () {
    const a = [];
    for (let i = 0; i < arguments.length; i++) a.push(arguments[i]);
    return body(origFn, a);                // a[0] = self, a[1] = _cmd, a[2..] = args
  }, mm.returnType, mm.argumentTypes);
  ObjC.api.method_setImplementation(mm.handle, cb);
  keepAlive.push(cb);
}
```

Notes that decide whether this works:

- **Both directions must be replaced.** If the app creates the object through a class
  method and mutates it through an instance initializer, hooking only the class method
  leaves a path open (classic: `+[Model fromX:]` and `-[Model initWithX:]`).
- **Signature fidelity.** `mm.returnType` / `mm.argumentTypes` come from the type
  encoding; use them as-is, do not hardcode.
- **Never wrap integer/BOOL arguments in `new ObjC.Object(a[n])`** — that dereferences a
  value as a pointer and segfaults at an address equal to the integer.
- `ObjC.api.sel_registerName(...)` does not accept a JS string; pass
  `Memory.allocUtf8String("foo:")`.
- Keep every `NativeCallback` alive (the `keepAlive` array). A collected callback is a
  guaranteed crash on the next call.
- If the target is ARM64 and the method returns a struct, `NativeCallback` return type
  must be the struct encoding; otherwise the call corrupts x0/x1.

## When the proxy can't see a method

`ObjC.classes.Foo['- setBar:']` can exist while `foo.setBar_(1)` throws
`TypeError: not a function` (tagged pointers / dynamic resolution / odd encodings).
Call through the runtime directly:

```js
const msgSend = new NativeFunction(Module.findGlobalExportByName("objc_msgSend"), "void",
                                   ["pointer", "pointer", "long"]);
msgSend(foo.handle, ObjC.selector("setBar:"), 1);
```

## Capturing instances for later use

- `objc_retain` anything you stash from a hook; otherwise it is deallocated and you get a
  use-after-free later (often as `EXC_BAD_ACCESS / SIGBUS`, code 0x2).
- **Cap what you keep.** One session accumulated every detector instance it saw (`16531`
  objects) and the 1 Hz loop then fed all of them — the app died. Keep the newest one
  (`this.detector = ...`), not a list.
- Prefer driving the app's own state machine from a single retained instance over
  re-entering hooks.

## Timing: `-f` runs before `main`

With `frida -f` (spawn), the script is evaluated **before** the app's `main`. Touching
Foundation synchronously at that point (e.g. `NSHomeDirectory`, building `NSString`s) can
crash the process. Defer the first such call (a `setTimeout`, or the first hook hit), and
do UI/Foundation work on `ObjC.schedule(ObjC.mainQueue, ...)`.

## One session per app

A second Frida session attaching to the same app while the first is attached makes
`create_script` time out, and hooks that "installed" never fire. Kill the old session
(`device.kill` / `frida-kill`) before starting a new one.
