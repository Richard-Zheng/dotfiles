// Bridge-free Objective-C introspection (Frida >= 17: no ObjC global needed).
// rpc.exports.classesImplementing(sel) / .typeEncoding(cls, sel) / .classMethods(cls)
// / .respondsTo(cls, sel) / .describe(sel)

function sym(name) {
  try { if (Module.getGlobalExportByName) return Module.getGlobalExportByName(name); } catch (e) {}
  try { return Module.findGlobalExportByName(name); } catch (e) {}
  return null;
}

const _cls   = new NativeFunction(sym("objc_getClass"), "pointer", ["pointer"]);
const _list  = new NativeFunction(sym("objc_getClassList"), "int", ["pointer", "int"]);
const _name  = new NativeFunction(sym("class_getName"), "pointer", ["pointer"]);
const _sel   = new NativeFunction(sym("sel_registerName"), "pointer", ["pointer"]);
const _gim   = new NativeFunction(sym("class_getInstanceMethod"), "pointer", ["pointer", "pointer"]);
const _gcm   = new NativeFunction(sym("class_getClassMethod"), "pointer", ["pointer", "pointer"]);
const _enc   = new NativeFunction(sym("method_getTypeEncoding"), "pointer", ["pointer"]);
const _nargs = new NativeFunction(sym("method_getNumberOfArguments"), "uint", ["pointer"]);
const _rtype = new NativeFunction(sym("method_getReturnType"), "void", ["pointer", "pointer", "size_t"]);
const _resp  = new NativeFunction(sym("class_respondsToSelector"), "bool", ["pointer", "pointer"]);
const _super = new NativeFunction(sym("class_getSuperclass"), "pointer", ["pointer"]);
const _mname = new NativeFunction(sym("method_getName"), "pointer", ["pointer"]);
const _imp   = new NativeFunction(sym("method_getImplementation"), "pointer", ["pointer"]);
const _selname = new NativeFunction(sym("sel_getName"), "pointer", ["pointer"]);

const utf8 = (p) => { try { return p.isNull() ? null : p.readUtf8String(); } catch (e) { return null; } };

function allClasses() {
  const n = _list(ptr(0), 0);
  const buf = Memory.alloc(n * Process.pointerSize);
  const got = _list(buf, n);
  const out = [];
  for (let i = 0; i < got; i++) {
    const c = buf.add(i * Process.pointerSize).readPointer();
    if (!c.isNull()) out.push(c);
  }
  return out;
}

rpc.exports = {
  sym: (n) => { const p = sym(n); return p ? p.toString() : null; },

  classesImplementing(selName) {
    const want = _sel(Memory.allocUtf8String(selName));
    const hits = [];
    for (const cls of allClasses()) {
      if (!_gim(cls, want).isNull()) hits.push(utf8(_name(cls)));
      else if (!_gcm(cls, want).isNull()) hits.push("+" + utf8(_name(cls)));
    }
    return hits;
  },

  // Like classesImplementing, but tells inherited from owned: same IMP + superclass chain
  // means "inherited", a distinct IMP means "this class really implements it".
  // Selector names collide across unrelated classes, so check the IMP before trusting a hit.
  implementors(selName) {
    const want = _sel(Memory.allocUtf8String(selName));
    const out = [];
    for (const cls of allClasses()) {
      const m = _gim(cls, want);
      if (m.isNull()) continue;
      const chain = [];
      let p = cls;
      while (!p.isNull() && chain.length < 12) { chain.push(utf8(_name(p))); p = _super(p); }
      out.push({ cls: chain[0], imp: _imp(m).toString(), chain });
    }
    return out;
  },

  respondsTo(className, selName) {
    const cls = _cls(Memory.allocUtf8String(className));
    if (cls.isNull()) throw new Error("no such class: " + className);
    const want = _sel(Memory.allocUtf8String(selName));
    return { instance: _resp(cls, want), classMethod: !_gcm(cls, want).isNull() };
  },

  typeEncoding(className, selName) {
    const cls = _cls(Memory.allocUtf8String(className));
    if (cls.isNull()) throw new Error("no such class: " + className);
    const want = _sel(Memory.allocUtf8String(selName));
    let m = _gim(cls, want);
    if (m.isNull()) m = _gcm(cls, want);
    if (m.isNull()) throw new Error("no such method: " + className + " " + selName);
    const buf = Memory.alloc(128);
    _rtype(m, buf, 128);
    return {
      encoding: utf8(_enc(m)),
      returnType: utf8(buf),
      argCount: _nargs(m),
    };
  },

  classMethods(className) {
    // Enumerates a class's own methods via the runtime's method lists is not exposed
    // through a stable API; use ObjC.classes in the REPL, or query specific selectors.
    const cls = _cls(Memory.allocUtf8String(className));
    if (cls.isNull()) throw new Error("no such class: " + className);
    return { name: className, superclass: utf8(_name(_super(cls))) };
  },

  // Dump type encodings for many selectors at once (cheap safety check before mass calls).
  encodings(className, selectors) {
    const out = {};
    for (const s of selectors) {
      try { out[s] = this.typeEncoding(className, s); } catch (e) { out[s] = { error: String(e) }; }
    }
    return out;
  },
};

send({ tag: "ready", pid: Process.id, classes: allClasses().length });
