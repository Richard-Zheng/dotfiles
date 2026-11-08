# iOS StoreKit / IAP from Frida

How to answer "does this SKU exist", "what did the app actually ask the App Store for", and
"can I change what it buys" — without touching the app's own gating code.

Applies to the **StoreKit 1** surface (`SKProductsRequest`, `SKPaymentQueue`, `SKMutablePayment`),
which is what almost every shipping app still uses for the actual transaction even when it reads
offers through StoreKit 2. All recipes below were verified end-to-end on iOS 16.

## 0. Two data planes, and why that matters

| Plane | Source | Who consumes it | Consequence |
| --- | --- | --- | --- |
| **Catalogue** | app's own backend (web API), e.g. `{"a":"utqa"}` → JSON with `ios` / `google` product ids, price, quota, cycle | the app's UI and its purchase gate | Plan missing from the catalogue = invisible in the UI, even if the SKU is sellable |
| **Store** | App Store Connect, queried by `SKProductsRequest` | StoreKit itself | Only the store decides whether a product id is purchasable |

So "the app doesn't offer plan X" can mean two very different things, and you should not
confuse them: the SKU may be `invalid` in the store, or perfectly valid but not handed out by
the backend. Probe the store before concluding anything about the product roadmap — and expect
they can disagree *in both directions*.

The corollary is the useful trick: **hook at the sink, not at the gate.** The app gates on its
catalogue long before StoreKit is involved; rewriting what reaches `SKPaymentQueue` sidesteps
every client-side check without faking a single `SKProduct`.

## 1. Locate the chain first

Grep the app (or its dylib) for the four landmarks, then read outward:

```sh
rg -n "SKPaymentQueue|SKMutablePayment|SKProductsRequest|paymentDiscount|productIdentifier" 
rg -n "addPayment|purchaseProduct|restoreCompletedTransactions|submitPurchase|verifyReceipt"
```

Typical shape (Clean-Architecture apps add two or three hops in front of it, but the tail is
always the same):

```
UI tap
  → view model / use case          (may check eligibility, active subscription, …)
  → repository.purchasePlan(id)    ← catalogue lookup: "is this id in our plan list?"
  → [AppPurchase purchaseProduct:(SKProduct)]
  → SKMutablePayment(product:)     ← offer/intro discount attached here
  → [SKPaymentQueue addPayment:]   ← THE SINK. nothing else validates from here on
  → App Store sheet / payment
  → paymentQueue:updatedTransactions: → receipt → app backend
```

The `SKProduct` handed to `purchaseProduct:` can only exist if the catalogue contained its id,
which is why the gate cannot be bypassed above this point — and why it does not matter below it.

## 2. Hook map

| Selector / class | Why | Notes |
| --- | --- | --- |
| `-[SKProductsRequest initWithProductIdentifiers:]` | see the exact id set the app asks the store for | args[2] is an `NSSet`; `allObjects()` → `NSArray` |
| `-[<App> productsRequest:didReceiveResponse:]` | what the store answered: `products` + `invalidProductIdentifiers` | the decisive catalogue-vs-store comparison |
| `-[SKMutablePayment initWithProduct:]` | optional; **often absent** — Swift's `SKMutablePayment(product:)` may not leave this selector behind | don't depend on it |
| `-[SKPaymentQueue addPayment:]` | the sink: last point before the sheet | 100% present; the rewrite point |
| `-[SKPayment paymentWithProduct:]` / `+…` | alternative sink for older code paths | check which one exists |
| `- paymentQueue:updatedTransactions:` | results: `Purchasing / Purchased / Restored / Failed / Deferred` | `Deferred` (Ask to Buy) needs the HUD dismissed by the app, watch for freezes |
| `- paymentQueueRestoreCompletedTransactionsFinished:` | restore outcome | pairs with `restoreCompletedTransactions` |

Missing selectors are normal: log them and move on (`ObjC.classes.X["- sel:"]` returns
`null`/`undefined` when the version does not have it). Do not let one absent hook stop the run.

## 3. Recipe: rewrite what gets bought (verified)

`SKMutablePayment.productIdentifier` is **read-write** (plain `SKPayment`'s is not), so no new
`SKProduct` is needed — a string swap is enough:

```js
const TARGET = "com.example.app.plan.monthly";   // the SKU you want instead

Interceptor.attach(ObjC.classes.SKPaymentQueue["- addPayment:"].implementation, {
  onEnter(args) {
    const payment = new ObjC.Object(args[2]);
    const before = payment.productIdentifier().toString();
    if (before === TARGET) return;

    try {
      payment.setProductIdentifier_(TARGET);
      send({ tag: "rewrite", how: "setProductIdentifier", before, after: payment.productIdentifier().toString() });
    } catch (e) {
      // fallback: hand the queue a fresh payment object built from scratch
      const fresh = ObjC.classes.SKMutablePayment.alloc().init();
      fresh.setProductIdentifier_(TARGET);
      try { fresh.setQuantity_(payment.quantity()); } catch (e2) {}
      try { fresh.setApplicationUsername_(payment.applicationUsername()); } catch (e2) {}
      args[2] = fresh.handle;                  // keep a JS reference, or ARC eats it
      send({ tag: "rewrite", how: "newPaymentObject", before, after: TARGET });
    }
  }
});
```

Notes that cost time:

- Keep the replacement in a JS array (`keepAlive.push(fresh)`); a payment released before
  `add:` runs is a `EXC_BAD_ACCESS` inside StoreKit.
- If the app attaches a promotional offer (`payment.paymentDiscount`), a fresh object loses it —
  copy `paymentDiscount` too if you care about the discounted price.
- If the app sets `applicationUsername` for receipt binding, the value must usually become `""`
  for a signed promotional offer; that mismatch is app-specific, not a Frida problem.

## 4. Recipe: does this SKU exist at all (verified)

No app interaction needed: run your own `SKProductsRequest` from inside the target process (the
app's bundle id is what scopes the request, so it must be *this* process). Valid ids come back in
`products`, unknown ones in `invalidProductIdentifiers`.

```js
const keep = [];                                   // ARC
const Probe = ObjC.registerClass({
  name: "FridaSKProbe",
  superClass: ObjC.classes.NSObject,
  protocols: [ObjC.protocols.SKProductsRequestDelegate, ObjC.protocols.SKRequestDelegate],
});

// add the delegate methods with RAW IMPs: see §6 for why registerClass's
// plain-function form silently drops the arguments
function addRaw(cls, sel, enc, fn) {
  const cb = new NativeCallback(fn, "void", ["pointer", "pointer", "pointer", "pointer"]);
  ObjC.api.class_addMethod(
    cls.handle,
    ObjC.api.sel_registerName(Memory.allocUtf8String(sel)),   // raw runtime: takes a C string pointer
    cb,
    Memory.allocUtf8String(enc));
  keep.push(cb);
}

let resolveProbe = null;
addRaw(Probe, "productsRequest:didReceiveResponse:", "v@:@@", (self, cmd, request, response) => {
  const r = new ObjC.Object(response);
  const valid = [], invalid = [], details = [];
  const prods = r.products();
  for (let i = 0; i < prods.count(); i++) {
    const p = prods.objectAtIndex_(i);
    valid.push(p.productIdentifier().toString());
    details.push({ id: p.productIdentifier().toString(),
                   title: p.localizedTitle().toString(),
                   price: p.price().toString() });
  }
  const inv = r.invalidProductIdentifiers();
  for (let i = 0; i < inv.count(); i++) invalid.push(inv.objectAtIndex_(i).toString());
  if (resolveProbe) resolveProbe({ valid, invalid, details });
});
addRaw(Probe, "request:didFailWithError:", "v@:@@", () => { if (resolveProbe) resolveProbe({ error: "request failed" }); });

rpc.exports.probe = (ids) => new Promise((resolve) => {
  resolveProbe = resolve;
  const delegate = Probe.alloc().init();           // NOT `new Probe()` — registerClass returns an ObjC.Object
  keep.push(delegate);
  const arr = ObjC.classes.NSMutableArray.array();
  ids.forEach((id) => arr.addObject_(ObjC.classes.NSString.stringWithString_(id)));
  const req = ObjC.classes.SKProductsRequest
    .alloc()
    .initWithProductIdentifiers_(ObjC.classes.NSSet.setWithArray_(arr));
  req.setDelegate_(delegate);
  keep.push(req);                                   // a released request never calls back
  req.start();
});
```

Expected output shape — always include controls, so a global failure is distinguishable from a
per-id answer:

```
valid  : com.example.yearly   -> "PRO LITE Yearly"   price=3499.99
valid  : com.example.monthly  -> "PRO LITE Monthly"  price=249.99    ← the question
invalid: com.example.nonsense
```

`localizedTitle` is the fastest way to see what the SKU really is: the App Store title often
differs from the app's internal plan name, and the price is the local-store price (not the
backend's price).

## 5. Recipe: what did the app ask for, and what came back

Hook the app's own delegate instead of running your own request. This needs no bridge-side
delegate, no lifetimes, and shows the app's real id set (which is your catalogue-vs-store diff):

```js
Interceptor.attach(ObjC.classes.AppPurchase["- productsRequest:didReceiveResponse:"].implementation, {
  onEnter(args) {
    const r = new ObjC.Object(args[3]);
    send({
      tag: "catalogue",
      valid: toStrings(r.products()),
      invalid: toStrings(r.invalidProductIdentifiers()),
    });
  }
});
```

Run it *before* the app loads pricing (attach early, or you will see nothing because the
catalogue is loaded once and cached), then drive the purchase screen.

## 6. Bridge mechanics that bite (all verified)

| Symptom | Cause | Fix |
| --- | --- | --- |
| JS method in `registerClass`/`implement` gets only 2 args: `arguments.length === 2`, so `response` is `undefined` and `TypeError: cannot read property 'x' of undefined` | the plain-function form has no type signature of its own; the bridge guesses `types` from the superclass/protocol key and can end up with a 0-argument selector, so the arguments are never forwarded | don't trust it — log `arguments.length` once; for anything with arguments add the IMP yourself: `ObjC.api.class_addMethod(cls, sel, new NativeCallback(...), "v@:@@")` |
| `Error: expected a pointer` from `ObjC.api.*` | `ObjC.api` is the **raw** runtime: it takes `NativePointer`s, not JS strings | `ObjC.api.sel_registerName(Memory.allocUtf8String(sel))` |
| `TypeError: not a constructor` on a registered class | `ObjC.registerClass` returns an `ObjC.Object` (the class object) | `Cls.alloc().init()` |
| `proxy: cannot set property` when stashing a tag on a delegate | ObjC proxies reject arbitrary JS fields | keep a `Map` keyed by `String(obj.handle)` |
| request/delegate never calls back | the request or the delegate was released (ARC) | keep the request, the delegate **and** the `NativeCallback` in a JS array |
| callback fires but with `nil` | the store answered with nil `products` (e.g. no network, no signed-in Apple ID) | read `invalidProductIdentifiers` too; `nil` ≠ "no arguments" |
| hooks installed, nothing fires | pricing was loaded before you attached (cached), or the app uses StoreKit 2 | attach before the screen appears, or hook the Swift call site instead |

Type encodings for object-argument methods: `"v@:@@"` for two object args, `"v@:@"` for one.
`@` = object, `v` = void, `:` = selector.

## 7. Where it stops

- **Receipts are the source of truth.** The app posts the App Store receipt to its backend; the
  backend decides the entitlement. Changing the SKU changes what Apple charges you — it does not
  by itself grant anything the backend refuses. Test the *whole* path, not just the sheet.
- **UI lies after a rewrite.** Prices and quotas displayed come from the catalogue, the charge
  comes from the store, so the screen can show one plan while a different one is bought.
- **Subscriptions live on the Apple ID.** Cancel/refund through the App Store; `restoreCompleted­Transactions`
  in the app is what re-syncs the backend later, so a hidden plan can still show up after a
  restore (which is a great way to confirm what was really purchased).
- **StoreKit 2 purchases** go through Swift async `Product.purchase()`; there is no simple ObjC
  sink. If the app has already migrated, hook its Swift wrapper (find the owning class, then use
  `ObjC.classes[...]` or a symbol breakpoint) rather than chasing StoreKit internals.
- **Only do this on your own device and your own account.** It is a debugging technique for
  answering questions about your app, not a distribution strategy, and it can spend real money.

## 8. Checklist

1. Probe the store for the id set (controls included) → is the SKU real?
2. Hook the app's `productsRequest:didReceiveResponse:` → is it in the catalogue the app sees?
3. Hook `addPayment:` → what does the app hand to StoreKit, and with which discount?
4. Rewrite `productIdentifier` there if the answer is "sellable but not offered".
5. Verify at the far end: `updatedTransactions` state, receipt submission result, and the plan
   the account shows after a `restoreCompletedTransactions`.
