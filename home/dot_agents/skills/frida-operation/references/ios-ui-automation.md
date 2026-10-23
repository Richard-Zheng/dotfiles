# Driving an iOS UI from Frida (no touch injection)

Touch injection via private APIs (`IOHIDEventSystemClientDispatchEvent`) needs
`com.apple.private.hid.client.event-dispatch`; a re-signed app has empty entitlements, so
it silently does nothing. Screen capture via `CARenderServerRenderDisplay` needs
`com.apple.QuartzCore.global-capture` — same story. **Do it through UIKit instead.**

## The loop: read the tree → act on the control

```js
function walk(v, depth = 0, out = []) {
  const cls = v.$className;
  let text = null;
  try { text = v.text().toString(); } catch (e) {}            // UILabel / UITextField
  if (text === null) { try { text = v.currentTitle().toString(); } catch (e) {} }
  out.push({ path: v.path ? v.path.toString() : "", cls, text, frame: v.frame() });
  const subs = v.subviews();
  for (let i = 0; i < subs.count(); i++) walk(subs.objectAtIndex_(i), depth + 1, out);
  return out;
}
```

- `view.path` gives the index chain (`0.0.0.0.7`) — a stable handle for "click that node".
- Match by `$className` **and** text; class names alone collide (and private classes get
  renamed between builds).
- **Do not use `v.respondsToSelector_('text')` as a guard.** Under Frida 17 it can return
  false for views that do respond, which silently turns every label into `null`.
  `try { v.text() } catch (e) {}` is version-proof.

## Acting on controls

| Control | Action |
| --- | --- |
| `UIButton` | `sendActionsForControlEvents_(1 << 6)` (touchUpInside) |
| `UITextField` | `setText_("...")` **then** `sendActionsForControlEvents_(1 << 17)` (editingChanged) — without the second call the app's state doesn't update and the submit button stays disabled |
| `UISwitch` | `setOn:animated:` or the control event |
| `UIScrollView` | `setContentOffset:animated:` |
| Custom button subclass | it inherits the control events; read state with `isSelected()` |

Slider/gesture/CAPTCHA interactions have no view-tree equivalent — those need real HID
injection (i.e. a tweak with entitlements, or a physical device). Know when to stop.

## Struct-returning methods come back as JS arrays

`UIScreen.mainScreen().bounds()` → `[[0,0],[390,844]]` (origin at `[0]`, size at `[1]`),
`-[MKAnnotation coordinate]` → `[lat, lng]`. Reading `.size.width` gives `undefined`, and
code that then falls back to defaults looks like "the API returns nothing".

## Passing collections

`NSArray.arrayWithArray_([a.handle, b.handle])` throws `Error: expected a pointer`.
Either pass `ObjC.Object` values (not handles), or build incrementally:

```js
const d = ObjC.classes.NSMutableDictionary.dictionary();
d.setObject_forKey_(value, key);
```

## Screenshot from inside the app (no Xcode, no idevicescreenshot)

Renders the window's layer tree to PNG with CoreGraphics, then reads the bytes back. Run
it on the main queue; write into the app's own `NSTemporaryDirectory()` — writing to
`/var/mobile/...` fails with "Operation not permitted".

```js
ObjC.schedule(ObjC.mainQueue, () => {
  const g = Module.findGlobalExportByName;
  const bmp  = new NativeFunction(g("CGBitmapContextCreate"), "pointer",
                ["pointer","ulong","ulong","ulong","ulong","pointer","uint"]);
  const cs   = new NativeFunction(g("CGColorSpaceCreateDeviceRGB"), "pointer", []);
  const toImg= new NativeFunction(g("CGBitmapContextCreateImage"), "pointer", ["pointer"]);
  const png  = new NativeFunction(g("UIImagePNGRepresentation"), "pointer", ["pointer"]);
  const scale= new NativeFunction(g("CGContextScaleCTM"), "void", ["pointer","double","double"]);
  const trans= new NativeFunction(g("CGContextTranslateCTM"), "void", ["pointer","double","double"]);

  const win = ObjC.classes.UIApplication.sharedApplication().keyWindow();
  const W = 390, H = 844, s = 2;
  const ctx = bmp(ptr(0), W*s, H*s, 8, W*s*4, cs(), 0x4001);   // RGBA premultipliedLast
  scale(ctx, s, s); trans(ctx, 0, H); scale(ctx, 1, -1);        // UIKit orientation
  win.layer().renderInContext_(ctx);
  const img = ObjC.classes.UIImage.imageWithCGImage_(toImg(ctx));
  const data = new ObjC.Object(png(img));
  const dir = ObjC.classes.NSFileManager.defaultManager().temporaryDirectory().path().toString();
  const f = new File(dir + "/shot.png", "wb");
  f.write(data.bytes().readByteArray(data.length())); f.close();
  send({ tag: "shot", path: dir + "/shot.png" });
});
```

Caveats: `renderInContext:` skips `AVPlayer`/Metal layers (video ads come out white);
use `drawViewHierarchyInRect:afterScreenUpdates:` if you need those. Multi-window apps
(SplashWindow overlays) need the window picked explicitly.

For a device-level loop, a persistent VNC client is faster than repeated one-shot
captures (one handshake, then ~0.5 s/frame).

## Debugging loop that actually converges

1. **Look at the screen** — confirms whether you are stuck on a dialog, a spinner, or a
   gate you did not know about.
2. **Read the app's own log file** if it writes one (DDLog/CocoaLumberjack style logs often
   carry the exact rejected reason).
3. **Take the error string from the UI/log into IDA**, find its xrefs, and decompile the
   function that produces it — that is the gate condition.
4. Stop swizzling getters once you find a *state machine*; gate the state, not the value.
