#!/usr/bin/env python3
"""Attach-or-spawn probe. No sleeps: every wait is an rpc call or a bounded event.

  probe.py --target MyApp --rpc info
  probe.py --target MyApp --rpc modules --limit 5
  probe.py --spawn /path/to/bin --argv a b --rpc info
  probe.py --target MyApp --agent custom.js --rpc customFn

Exit codes: 0 ok, 2 agent/attach error, 3 detached/crashed, 4 rpc error, 5 ready timeout.
"""
import argparse, json, os, sys, threading

import frida

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_AGENT = os.path.join(HERE, "..", "agents", "probe.js")


def connect(remote):
    if remote:
        return frida.get_device_manager().add_remote_device(remote)
    return frida.get_usb_device(timeout=5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--remote", default=os.environ.get("FRIDA_REMOTE", "127.0.0.1:27042"),
                    help="host:port of a frida-server tunnel (empty string = local/usb)")
    ap.add_argument("--target", help="process name or pid to attach to")
    ap.add_argument("--spawn", help="path to spawn instead of attach")
    ap.add_argument("--argv", nargs="*", default=[], help="argv for --spawn")
    ap.add_argument("--stdio", default="pipe", help="spawn stdio mode (default pipe)")
    ap.add_argument("--agent", default=DEFAULT_AGENT)
    ap.add_argument("--rpc", default="info")
    ap.add_argument("--rpc-args", default="[]",
                    help='JSON array of positional args for --rpc, e.g. \'["selName"]\'')
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--ready-timeout", type=float, default=10.0)
    ap.add_argument("--wait-exit", action="store_true",
                    help="after the rpc, wait for the target to exit (bounded, event-driven)")
    args = ap.parse_args()

    if not args.target and not args.spawn:
        ap.error("need --target or --spawn")

    dev = connect(args.remote or None)
    def on_output(pid, fd, data):          # stream, do not buffer: no post-hoc race
        text = data.decode("utf8", "replace")
        if text:
            print(("[stdout] " if fd == 1 else "[stderr] ") + text.rstrip(), file=sys.stderr, flush=True)
    dev.on("output", on_output)
    dev.on("process-crashed", lambda pid, crash: print("!! crashed", pid, crash.report, file=sys.stderr))

    if args.spawn:
        pid = dev.spawn([args.spawn] + args.argv, stdio=args.stdio)
        sess = dev.attach(pid)
    else:
        pid = None
        sess = dev.attach(args.target)

    detached = threading.Event()
    sess.on("detached", lambda reason, crash: (print(f"!! detached: {reason} crash={crash}", file=sys.stderr),
                                               detached.set()))

    ready = threading.Event()
    errors = []

    def on_msg(msg, data):
        if msg["type"] == "error":
            errors.append(msg.get("description", "agent error") + "\n" + msg.get("stack", ""))
            ready.set()
            return
        payload = msg.get("payload") or {}
        if payload.get("tag") == "ready":
            ready.set()
        elif payload.get("tag") == "exception":
            print("!! in-process exception:", payload, file=sys.stderr)

    script = sess.create_script(open(args.agent).read(), name="probe")
    script.on("message", on_msg)
    script.on("destroyed", lambda: ready.set())
    script.load()

    if args.spawn:
        dev.resume(pid)

    if not ready.wait(args.ready_timeout):
        print("!! agent did not report ready within %.1fs" % args.ready_timeout, file=sys.stderr)
        return 5
    if errors:
        print("!! agent error:\n" + "\n".join(errors), file=sys.stderr)
        return 2
    if detached.is_set():
        return 3

    try:
        call_args = json.loads(args.rpc_args)
        if not isinstance(call_args, list):
            ap.error("--rpc-args must be a JSON array")
        result = getattr(script.exports_sync, args.rpc)(*call_args)
    except Exception as e:                                    # noqa: BLE001
        print(f"!! rpc {args.rpc} failed: {e}", file=sys.stderr)
        return 4

    if args.limit and isinstance(result, list):
        result = result[: args.limit]
    print(json.dumps(result, indent=2, ensure_ascii=False))

    if args.wait_exit:
        if not detached.wait(args.ready_timeout):
            print("!! target still running after %.1fs" % args.ready_timeout, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
