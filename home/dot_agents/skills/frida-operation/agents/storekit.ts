/* StoreKit 1 toolkit — probe / observe / rewrite.
 *
 * Needs the ObjC bridge compiled in (Frida >= 17 ships none):
 *   npm i frida-objc-bridge
 *   python3 -c 'import frida; open("storekit.js","w").write(frida.Compiler().build("/abs/path/storekit.ts"))'
 *   script = session.create_script(open("storekit.js").read(), runtime="qjs")
 *   script.load(); script.exports_sync.set_rewrite("com.example.plan.monthly")
 *
 * rpc.exports:
 *   probe(ids)        -> { valid, invalid, details }  "does the App Store know these SKUs?"
 *   setRewrite(id)    -> enable/disable the addPayment: rewrite (null = off)
 *   state()           -> { rewriteTo, hookedAddPayment, hookedCatalogue }
 *
 * events (send): { t: "log" | "catalogue" | "buy" | "addPayment" | "rewrite" }
 */
import ObjCModule from "frida-objc-bridge";

const ObjC: any = ObjCModule;
const send0 = (o: any) => send(o);
const log = (msg: string) => send0({ tag: "log", msg });

let rewriteTo: string | null = null;
const keepAlive: any[] = [];          // ARC: requests, delegates, IMP callbacks, replacements
const hooked = { addPayment: false, catalogue: false };

/* Skip this if the app class name is unknown; the probe half works without it.
 * Point it at the class that implements SKProductsRequestDelegate in your target
 * (the grep landmark is `productsRequest:didReceiveResponse:`). */
const APP_PURCHASE_CLASS = "MEGAPurchase";

function strs(arr: any): string[] {
  const out: string[] = [];
  if (arr === null || arr === undefined) return out;
  for (let i = 0; i < arr.count(); i++) out.push(arr.objectAtIndex_(i).toString());
  return out;
}

function selPointers(sel: string): NativePointer {
  // ObjC.api is the raw runtime: C string pointers, not JS strings
  return ObjC.api.sel_registerName(Memory.allocUtf8String(sel));
}

function addRaw(cls: any, sel: string, enc: string, argCount: number, fn: any) {
  const types: any[] = ["pointer", "pointer"];
  for (let i = 0; i < argCount; i++) types.push("pointer");
  const cb: any = new NativeCallback(fn, "void", types as any);
  ObjC.api.class_addMethod(cls.handle, selPointers(sel), cb, Memory.allocUtf8String(enc));
  keepAlive.push(cb);
}

/* ---------------------------------------------------------------- probe ---- */

let resolveProbe: ((v: any) => void) | null = null;

const Probe = ObjC.registerClass({
  name: "FridaSKProbe" + (Date.now() % 100000),   // unique: re-attaching must not collide
  superClass: ObjC.classes.NSObject,
  protocols: [ObjC.protocols.SKProductsRequestDelegate, ObjC.protocols.SKRequestDelegate],
});

addRaw(Probe, "productsRequest:didReceiveResponse:", "v@:@@", 2,
  (self: any, cmd: any, request: any, response: any) => {
    const out: any = { valid: [], invalid: [], details: [] };
    try {
      const r = new ObjC.Object(response);
      const prods = r.products();
      for (let i = 0; i < prods.count(); i++) {
        const p = prods.objectAtIndex_(i);
        const id = p.productIdentifier().toString();
        out.valid.push(id);
        const d: any = { id };
        try { d.title = p.localizedTitle().toString(); } catch (e) {}
        try { d.price = p.price().toString(); } catch (e) {}
        try { d.locale = p.priceLocale().localeIdentifier().toString(); } catch (e) {}
        out.details.push(d);
      }
      out.invalid = strs(r.invalidProductIdentifiers());
    } catch (e) {
      out.error = String(e);
    }
    if (resolveProbe) { resolveProbe(out); resolveProbe = null; }
  });

addRaw(Probe, "request:didFailWithError:", "v@:@@", 2,
  (self: any, cmd: any, request: any, error: any) => {
    let msg = "request failed";
    try { msg = new ObjC.Object(error).localizedDescription().toString(); } catch (e) {}
    if (resolveProbe) { resolveProbe({ error: msg }); resolveProbe = null; }
  });

/* ---------------------------------------------------------------- hooks ---- */

function hook(cls: any, sel: string, onEnter: (args: any) => void, label: string): boolean {
  try {
    if (!cls) { log("skip (class missing): " + label); return false; }
    const m = cls[sel];
    if (!m) { log("skip (selector missing): " + label); return false; }
    Interceptor.attach(m.implementation, { onEnter });
    log("hooked: " + label);
    return true;
  } catch (e) {
    log("hook failed: " + label + " -- " + e);
    return false;
  }
}

/* the sink: last stop before the payment sheet */
hooked.addPayment = hook(ObjC.classes.SKPaymentQueue, "- addPayment:", (args) => {
  let payment: any;
  try { payment = new ObjC.Object(args[2]); } catch (e) { return; }
  let before = "<none>";
  try { before = payment.productIdentifier().toString(); } catch (e) {}
  let cls = "?";
  try { cls = payment.$className; } catch (e) {}
  send0({ tag: "addPayment", id: before, cls, rewriteTo });

  if (!rewriteTo || before === rewriteTo) return;

  try {
    payment.setProductIdentifier_(rewriteTo);              // SKMutablePayment: read-write
    send0({ tag: "rewrite", how: "setProductIdentifier", from: before, to: payment.productIdentifier().toString() });
    return;
  } catch (e) {
    send0({ tag: "rewrite", how: "setProductIdentifier", error: String(e) });
  }

  try {                                                     // fallback: brand new payment
    const fresh = ObjC.classes.SKMutablePayment.alloc().init();
    fresh.setProductIdentifier_(rewriteTo);
    try { fresh.setQuantity_(payment.quantity()); } catch (e) {}
    try { fresh.setApplicationUsername_(payment.applicationUsername()); } catch (e) {}
    try { if (payment.paymentDiscount) fresh.setPaymentDiscount_(payment.paymentDiscount()); } catch (e) {}
    keepAlive.push(fresh);
    args[2] = fresh.handle;
    send0({ tag: "rewrite", how: "newPaymentObject", from: before, to: rewriteTo });
  } catch (e) {
    send0({ tag: "rewrite", how: "newPaymentObject", error: String(e) });
  }
}, "SKPaymentQueue -addPayment:");

/* what the app decided to buy, straight from the SKProduct */
hooked.catalogue = hook(ObjC.classes[APP_PURCHASE_CLASS], "- productsRequest:didReceiveResponse:", (args) => {
  try {
    const r = new ObjC.Object(args[3]);
    const valid: string[] = [];
    const prods = r.products();
    for (let i = 0; i < prods.count(); i++) valid.push(prods.objectAtIndex_(i).productIdentifier().toString());
    send0({ tag: "catalogue", valid, invalid: strs(r.invalidProductIdentifiers()) });
  } catch (e) {
    log("catalogue hook err " + e);
  }
}, APP_PURCHASE_CLASS + " -productsRequest:didReceiveResponse:");

hook(ObjC.classes[APP_PURCHASE_CLASS], "- purchaseProduct:", (args) => {
  try {
    const p = new ObjC.Object(args[2]);
    send0({ tag: "buy", id: p.productIdentifier().toString() });
  } catch (e) {}
}, APP_PURCHASE_CLASS + " -purchaseProduct:");

/* ------------------------------------------------------------------ rpc ---- */

rpc.exports = {
  probe(ids: string[]) {
    return new Promise((resolve) => {
      resolveProbe = resolve;
      const delegate = Probe.alloc().init();               // not `new Probe()`
      keepAlive.push(delegate);
      const arr = ObjC.classes.NSMutableArray.array();
      for (const id of ids) arr.addObject_(ObjC.classes.NSString.stringWithString_(id));
      const req = ObjC.classes.SKProductsRequest
        .alloc()
        .initWithProductIdentifiers_(ObjC.classes.NSSet.setWithArray_(arr));
      req.setDelegate_(delegate);
      keepAlive.push(req);
      log("probe: " + ids.length + " ids");
      req.start();
    });
  },
  setRewrite(id: string | null) { rewriteTo = id || null; return rewriteTo; },
  state() { return { rewriteTo, hookedAddPayment: hooked.addPayment, hookedCatalogue: hooked.catalogue }; },
};

send({ tag: "ready", pid: Process.id, appClass: (ObjC.classes[APP_PURCHASE_CLASS] ? APP_PURCHASE_CLASS : null) });
log("storekit agent ready (app class: " + (ObjC.classes[APP_PURCHASE_CLASS] ? APP_PURCHASE_CLASS : "not found") + ")");
