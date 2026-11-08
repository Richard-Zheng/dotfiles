# iOS Quirks, Traps & Environment Gotchas

Runtime pitfalls and jailbreak environmental quirks distilled from practical instrumentation sessions.

---

## 1. Rootless Jailbreak & Tunnel Lifecycle

* **Port Forwarding**: The rootless `frida-server` binds loopback inside the device (`127.0.0.1:27042`). Tunnel via SSH:
  ```bash
  ssh -N -L 127.0.0.1:27042:127.0.0.1:27042 mobile@device
  ```
* **Tunnel Death**: Tunnels drop on device reboot or Wi-Fi sleep. Rebuild conditionally in host scripts:
  ```bash
  ss -ltn | grep -q 127.0.0.1:27042 || ssh -N -f -L 27042:127.0.0.1:27042 mobile@device
  ```
* **One Server Only**: A launchd-managed `frida-server` plus a manually spawned `-l 0.0.0.0:27042` copy produces `unexpected error while resuming process` or `timeout was reached`.
* **Clean Reset**: Do NOT `killall frida-server` on rootless iOS. Kickstart the launchd daemon cleanly:
  ```bash
  sudo launchctl kickstart -k system/re.frida.server
  ```

---

## 2. Version Parity & Session Constraints

* **Version Mismatch**: Host client (`frida --version`) and device server (`frida-server --version`) should match major versions. Mismatches masquerade as target bugs (`ProtocolError`, `TransactionError`).
* **Exactly One Session Per App**: A second session attaching while the first is active causes `create_script` to time out and hooks report false positives. Always detach or terminate old sessions first.

---

## 3. Spawn vs. Attach Execution Context

* **User Context**:
  - `dev.spawn([bundle_id])` launches through `frida-server`'s user (often `root`).
  - `uiopen --bundleid <id>` launches through launchd (`mobile` user context).
  - *Symptom*: If a target binary dies immediately under `spawn()` but runs fine normally, the issue is user launch context, not your script. Bring it to foreground via `uiopen` and `attach()`.
* **Suspended Background Apps**: Attaching to a suspended app yields `unexpected error while resuming process: (os/kern) failure`. Bring it forward (`uiopen -b <bundleid>`) before attaching.
* **Early Evaluation Window (`-f`)**: Agents loaded via spawn evaluate before `main()` during dynamic linker initialization (`dyld`). Accessing high-level Foundation APIs (`NSHomeDirectory`, allocating `NSString`) too early can fault. Defer setup using `Process.attachModuleObserver` or dispatch queues.

---

## 4. Code Signing & Memory Protection (`__TEXT`)

* **Never Modify Code Pages in Place**: On a signed iOS binary, flipping page permissions to writable invalidates the code-signing page hash. Subsequent execution faults with `SIGBUS KERN_PROTECTION_FAILURE` or `SIGILL` with a poisoned PC (`0xffffffffffffffff`).
* **Safe Alternatives**:
  - **IMP Swizzling**: Swaps runtime function pointers without modifying a single executable byte (see [ios-swizzle.md](./ios-swizzle.md)).
  - **Static Patch**: Patch binary bytes on disk (`dd` or Python) and re-sign with `ldid -S ent.plist`.

---

## 5. Common Anti-Debug Landmines

Before assuming Frida is broken, check for common defensive checks in the target binary:
* `sysctl(KERN_PROC_PID)` reading `kinfo_proc + 0x21` bit 3 (`P_TRACED = 0x800`).
* `ptrace(PT_DENY_ATTACH, 0, 0, 0)`.
* Dynamic calls to `sysctl` or `ptrace` via `dlsym`.
