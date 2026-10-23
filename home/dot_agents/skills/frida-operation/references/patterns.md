# No-sleep patterns

Every recipe here replaces a `sleep` with something that actually tells you the truth.

## 1. Do the work in the agent, return the answer

```js
// agent.js
rpc.exports = {
  info() {
    const m = Process.enumerateModules()[0];
    return { pid: Process.id, arch: Process.arch, first: m.name, base: m.base.toString() };
  },
  modules: () => Process.enumerateModules().map(m => ({ name: m.name, base: m.base.toString(), size: m.size })),
};
```

```python
script.load()          # sync: RPC is available on the next line
print(script.exports_sync.info())
```

`exports_sync` blocks until the agent's value arrives and raises on agent exceptions —
that is a *completion* wait, not a time wait.

## 2. Push instead of poll

```js
setTimeout(() => send({ tag: "ready", pid: Process.id }), 0);
// or from a hook:
//   send({ tag: "hit", fn: "mach_vm_write", addr: args[1].toString() });
```

```python
ready = threading.Event()
hits  = []
def on_msg(msg, data):
    if msg["type"] == "error":
        print("agent error:", msg["description"], msg.get("stack")); ready.set(); return
    p = msg.get("payload") or {}
    if p.get("tag") == "ready": ready.set()
    else: hits.append(p)
script.on("message", on_msg)
script.load()
if not ready.wait(10):
    raise SystemExit("agent never sent ready")
```

For high-rate streams, add a `queue.Queue` and drain it in one worker thread — do not
`append` from the callback and read without synchronization in another thread.

## 3. Wait for a module / a hit, without polling

```js
const once = (promiseFactory) => { /* ... */ };

rpc.exports.waitModule = (name, timeoutMs = 5000) => new Promise((resolve, reject) => {
  const hit = Process.findModuleByName(name);
  if (hit) return resolve({ name: hit.name, base: hit.base.toString() });
  const obs = Process.attachModuleObserver({ onAdded(m) { if (m.name === name) { obs.detach(); resolve({ name: m.name, base: m.base.toString() }); } } });
  setTimeout(() => { obs.detach(); reject(new Error("timeout " + name)); }, timeoutMs);
});

/// "resolve on the first call to a symbol", returns the captured args
rpc.exports.firstCall = (mod, sym, timeoutMs = 5000) => new Promise((resolve, reject) => {
  const addr = Module.findExportByName(mod, sym);
  if (!addr) return reject(new Error("no symbol " + sym));
  const listener = Interceptor.attach(addr, {
    onEnter(args) {
      listener.detach();
      resolve({ a0: args[0].toString(), a1: args[1].toString() });
    }
  });
  setTimeout(() => { listener.detach(); reject(new Error("timeout " + sym)); }, timeoutMs);
});
```

## 4. Know when the target dies

```python
sess.on("detached", lambda reason, crash: print("detached:", reason, crash))
dev.on("process-crashed", lambda pid, crash: print("crashed:", pid, crash.report))
```

In the agent, catch in-process faults so you can report *before* dying:

```js
Process.setExceptionHandler(d => {
  send({ tag: "exception", type: d.type, addr: d.address.toString() });
  return false;                      // let the process die afterwards
});
```

## 5. Spawn + stdio + resume (one shot)

```python
out = []
dev.on("output", lambda pid, fd, data: out.append((fd, data)))
pid = dev.spawn(["prog", "arg0"], stdio="pipe")     # argv passed directly
sess = dev.attach(pid)
script = sess.create_script(src); script.load()
dev.resume(pid)
# no sleep: wait for the agent's rpc, or for the detach event
```

## 6. Child processes

```python
dev.enable_spawn_gating()
dev.on("spawn-added", lambda spawn: (print("child:", spawn.pid, spawn.identifier), dev.resume(spawn.pid)))
```
Child gating is not available on every backend (notably iOS): check the platform first,
or brute-force with `enumerate_processes()` diffs if you must.

## 7. Patching "safely"

```js
// prefer this over addr.writeByteArray for code
Memory.patchCode(addr, 4, code => {
  const w = new Uint32Array(code.buffer);       // little-endian ARM64
  w[0] = 0xD503201F;                            // e.g. NOP
});
```

Still risky on iOS `__TEXT` of a signed binary (page invalidation → SIGBUS/SIGILL).
When a runtime patch crashes the app later, patch the file on disk and re-sign instead.

## 8. Message routing conventions that scale

```js
function emit(tag, payload) { send(Object.assign({ tag }, payload)); }
rpc.exports = {
  counters: () => counters,                     // pull
};
// push only edge events; pull for periodic state
```

Bounded RPC calls (`waitModule`, `firstCall`) keep the host free of timers while still
guarding against "nothing ever happens".

## 9. Common failure signatures

| Symptom | Cause |
| --- | --- |
| `typeof ObjC === "undefined"` | Frida >= 17, plain `create_script` (bridges unbundled) |
| crash PC `0xffffffffffffffff`, `SIGILL` | target's own tamper/anti-debug path, or a jump through a poisoned pointer |
| `SIGBUS KERN_PROTECTION_FAILURE` in `__TEXT` | patched a code page of a signed binary |
| `exports_sync` hangs | called from inside a `message` callback (re-entrancy) or agent threw before setting up |
| `TransactionError` / `ProtocolError` | client/server version skew, or the tunnel dropped |
