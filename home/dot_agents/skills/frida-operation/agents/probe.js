// Generic probe agent: no timers used for control flow, only for timeouts.
// API: rpc.exports.*  (call with script.exports_sync.<name>() from Python)

const _exceptions = [];

Process.setExceptionHandler(d => {
  _exceptions.push({ type: d.type, address: d.address.toString() });
  send({ tag: "exception", type: d.type, address: d.address.toString() });
  return false;                       // let it crash; the host sees "detached"
});

function modJson(m) {
  return { name: m.name, base: m.base.toString(), size: m.size, path: m.path };
}

globalThis.exceptions = _exceptions;

rpc.exports = {
  info() {
    const m = Process.mainModule;
    return {
      pid: Process.id,
      arch: Process.arch,
      pointerSize: Process.pointerSize,
      pageSize: Process.pageSize,
      mainModule: m ? modJson(m) : null,
      moduleCount: Process.enumerateModules().length,
      frida: Frida.version,
      runtime: Script.runtime,
    };
  },

  modules: () => Process.enumerateModules().map(modJson),

  threads: () => Process.enumerateThreads().map(t => ({ id: t.id, state: t.state, pc: t.context.pc.toString() })),

  // Resolve a symbol across all modules: "libsystem_kernel.dylib!task_for_pid" or just "task_for_pid".
  findSymbol(spec) {
    let p = null;
    if (spec.includes("!")) {
      const [mod, sym] = spec.split("!");
      p = Module.findExportByName(mod, sym);
    } else {
      p = Module.findGlobalExportByName(spec);
    }
    return p ? p.toString() : null;
  },

  // Wait for a module without polling.
  waitModule(name, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
      const hit = Process.findModuleByName(name);
      if (hit) return resolve(modJson(hit));
      const obs = Process.attachModuleObserver({
        onAdded(m) { if (m.name === name) { obs.detach(); resolve(modJson(m)); } }
      });
      setTimeout(() => { obs.detach(); reject(new Error("timeout waiting for " + name)); }, timeoutMs);
    });
  },

  // Resolve on the first call of an export; returns captured args as hex strings.
  firstCall(spec, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
      const p = this.findSymbol(spec);
      if (!p) return reject(new Error("symbol not found: " + spec));
      const addr = ptr(p);
      const listener = Interceptor.attach(addr, {
        onEnter(args) {
          listener.detach();
          const out = [];
          for (let i = 0; i < 6; i++) out.push(args[i].toString());
          resolve({ address: addr.toString(), args: out, caller: this.returnAddress.toString() });
        }
      });
      setTimeout(() => { listener.detach(); reject(new Error("timeout waiting for call: " + spec)); }, timeoutMs);
    });
  },

  exceptions: () => _exceptions.slice(),
};

send({ tag: "ready", pid: Process.id, frida: Frida.version });
