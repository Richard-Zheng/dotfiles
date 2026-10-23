# Bypass strategy: don't break the contract

Most "block the thing" hooks fail not because they are wrong, but because the caller was
waiting for a callback that now never comes. The general shapes below are portable.

## 1. Simulate the failure/close path, don't no-op the feature

If a component gates progress on a completion callback (splash ad finished, interstitial
closed, share sheet dismissed), making `show` a no-op means the callback never fires and
the app hangs — sometimes visibly ("stuck on splash"), sometimes as "the next screen never
loads data", which misleads you into hunting a network bug.

Read the delegate protocol first, then call the app's own failure/close callback with
`nil` arguments:

```js
swizzle("SomeManager", "- showAd", function (orig, a) {
  const self = new ObjC.Object(a[0]);
  self.fcAdFailedWithError_description_(null, null);   // app's own recovery path
});
```

Rule of thumb: **between two bad options, choose the one the app already knows how to
handle.** A failure callback is a code path the app was written to survive; an absent
callback is not.

Also mind *which* object you intercept. No-op'ing a shared base class or the splash
implementation itself can cascade (ads gone but startup stuck). Intercept the *entry point*
the app calls and steer it into the failure branch.

## 2. Pin the key, not the algorithm (app-layer crypto + MITM)

When a request body is encrypted by an app-layer scheme you cannot reimplement quickly,
hook the primitive and **overwrite the key buffer in place** with a known key, then let the
real code do the encryption:

```js
// CCCrypt(op, alg, options, key, keyLength, iv, in, inLength, out, outLength)
swizzle("CCCrypt", "- ", ...)          // or Interceptor.attach on the C function
// inside: if (op === 0 /* encrypt */ && alg === 0 /* AES */) -> memcpy(keyPtr, FIXED, 16)
```

Because both the request's ciphertext and its wrapped key derive from the same buffer, the
server still accepts the traffic (both changed consistently), and your proxy addon can
decrypt with the known key. This touches only system libraries, never the app's `__TEXT`,
so integrity checks stay quiet.

Practical notes: verify the key-buffer write with a read-back; confirm the *length* matches;
handle both directions (request encrypt, response decrypt); and match request signatures
exactly (a 15-character marker written as 16 never matches — count characters, don't guess).

## 3. Identify app-layer envelopes by shape, not by keywords

For "replace this response" hooks, keying on words like `"获取点位"` or `"5分钟"` misfires:
the same words appear in other endpoints' payloads, and you end up substituting the wrong
document (symptom: a detail screen that suddenly shows zeros). Match on the exact error
code plus a structural marker, and explicitly exclude other documents' unique fields:

```
if (body.includes('"error":10603') && body.includes('"pointsResModels"') && !body.includes('"rrid"'))
```

Then cache the *valid* response of that same endpoint and replay it. Caching a different
endpoint's response "that looks similar" is a trap that costs an hour.

## 4. Errors that look like network problems are usually state machines

Pattern: hook every getter to return legal values, still rejected. That means the gate is
not the value but a state variable (an enum: locating / ready / error) computed earlier.
Take the exact UI error string into IDA, follow its xrefs, and gate the state transition.
Related: values computed *before* your hook exists (a real GPS fix used as "last known
location") can poison later calculations; replace the object's construction, not just the
consumer.

## 5. Entitlement-gated private APIs

If a private API "runs but does nothing" (screenshots all zeros, injected touches ignored),
check entitlements before debugging the call sequence. A re-signed/decrypted app has
essentially none, so system services refuse the operation silently. Either use the public
path (UIKit) or run the code in a process that has the entitlement (a jailbreak daemon or a
tweak), not inside the app.
