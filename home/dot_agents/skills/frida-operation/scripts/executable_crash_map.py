#!/usr/bin/env python3
"""Map an Apple .ips crash report to image+offset and print the faulting stack.

.ips = one JSON line (header) + one JSON line (body). This walks `usedImages`,
resolves the fault address, and prints frames with symbol names. Far faster than
reading the raw report.

  crash_map.py /var/mobile/Library/Logs/CrashReporter/App-*.ips
  crash_map.py report.ips --json      # machine-readable summary
"""
import argparse, bisect, json, sys


def load(path):
    raw = open(path, encoding="utf8", errors="replace").read()
    head_line, sep, body_text = raw.partition("\n")
    if not sep:
        raise SystemExit("not an .ips (no second line)")
    try:
        head = json.loads(head_line)
    except json.JSONDecodeError:
        head = {}
    body = json.loads(body_text)
    return head, body


def image_table(body):
    imgs = body.get("usedImages") or []
    table = sorted((im.get("base", 0), im.get("size", 0), i) for i, im in enumerate(imgs))
    return imgs, table


def resolve(addr, imgs, table):
    bases = [t[0] for t in table]
    j = bisect.bisect_right(bases, addr) - 1
    if j < 0:
        return None, None
    base, size, idx = table[j]
    im = imgs[idx]
    if size and not (base <= addr < base + size):
        return None, None
    return im, addr - base


def summarize(head, body):
    exc = body.get("exception") or {}
    term = body.get("termination") or {}
    fault = None
    codes = (exc.get("codes") or "").split(",")
    if len(codes) == 2:
        try:
            fault = int(codes[1].strip(), 16)
        except ValueError:
            fault = None
    return {
        "proc": body.get("procName") or head.get("name"),
        "pid": body.get("pid") or head.get("pid"),
        "capture": body.get("captureTime"),
        "os": (body.get("osVersion") or {}).get("train"),
        "exception": exc.get("type"),
        "signal": exc.get("signal"),
        "subtype": exc.get("subtype"),
        "termination": term.get("indicator") or term.get("indicator"),
        "fault": fault,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--frames", type=int, default=16)
    args = ap.parse_args()

    head, body = load(args.path)
    info = summarize(head, body)
    imgs, table = image_table(body)
    fault = info["fault"]

    out = dict(info)
    if fault is not None:
        im, off = resolve(fault, imgs, table)
        out["fault_image"] = im.get("name") if im else None
        out["fault_offset"] = off

    ft = body.get("faultingThread") or 0
    threads = body.get("threads") or []
    frames_out = []
    if threads and ft < len(threads):
        for fr in (threads[ft].get("frames") or [])[: args.frames]:
            idx = fr.get("imageIndex")
            im = imgs[idx] if isinstance(idx, int) and idx < len(imgs) else {}
            frames_out.append({
                "image": im.get("name"),
                "base": im.get("base"),
                "offset": fr.get("imageOffset"),
                "symbol": fr.get("symbol") or "",
            })
    out["frames"] = frames_out

    if args.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return 0

    print(f"proc   : {out['proc']} (pid {out['pid']})  {out['os']}  {out['capture']}")
    print(f"signal : {out['exception']} / {out['signal']} {out['subtype'] or ''}  {out['termination'] or ''}")
    if fault is not None:
        if out.get("fault_image"):
            print(f"fault  : {fault:#x} -> {out['fault_image']}+{out['fault_offset']:#x}")
        else:
            print(f"fault  : {fault:#x} (not inside any image)")
    for i, fr in enumerate(frames_out):
        print(f"  #{i:<2} {str(fr['image']):<28} +{fr['offset']:#08x}  {fr['symbol']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
