# Arch Linux Dotfiles

Managed with [chezmoi](https://chezmoi.io). The repository holds **two** chezmoi
sources in one git tree:

```
home/   -> ~        (user dotfiles, applied by the normal `chezmoi` run)
root/   -> /        (system files, applied as root by `rootmoi`)
```

The split is signalled by [`.chezmoiroot`](https://www.chezmoi.io/reference/special-files/chezmoiroot/),
which points the user-level instance at `home/`.

## rootmoi

`root/` is applied by a second chezmoi instance that runs as root with
`destDir: /`. It is invoked through the `rootmoi` wrapper
(`~/.local/bin/rootmoi`), which is itself managed by the user-level instance.
After every `chezmoi apply`, `home/.chezmoiscripts/run_after_20-run-rootmoi.sh.tmpl`
runs `rootmoi apply` automatically. Set `NO_ROOTMOI=1` to skip it.

System files are declared under `root/etc/...`. Files owned by packages (like
`/etc/environment`) are merged with `modify_` templates instead of being
replaced wholesale.

## Machine profiles

The local chezmoi config (`.chezmoi.yaml.tmpl`) prompts once on `chezmoi init`
and stores two values:

- `type`: `desktop`, `laptop`, or `headless`
- `is_headless`: whether graphical desktop configuration should be excluded

It also detects the platform once and exposes it to all templates as data:
`is_linux`, `is_mac`, `is_arch`, `is_debian`. Installation scripts use
**capability detection** (does `pacman`/`apt-get`/`brew` exist?) rather than
branching on the OS, so the same scripts work across distributions.

After changing the config template on an existing machine, regenerate the local
config:

```sh
chezmoi init
```

## Snapshots of ~/proj

`~/proj` is a btrfs subvolume whose snapshots are managed by
[btrbk](https://digint.ch/btrbk/) (`root/etc/btrbk/btrbk.conf`). A per-minute
timer creates a snapshot only when the subvolume changed, keeping the last hour
in full plus the first snapshot of each of the last 10 hours. Snapshots are
stored in `~/.proj-snapshots`, outside the source subvolume.

## Optional AUR packages

- `selectdefaultapplication-fork-git` — set default applications for MIME types
  and URL schemes in `~/.config/mimeapps.list`

## carbon machine profile

Keep `type: laptop` and set `profile: carbon` in the local chezmoi config.
`chezmoi init` offers `generic` and `carbon`; a new host named carbon defaults
its profile to carbon. Existing configs without a profile keep generic behavior.
After selecting the profile, run `chezmoi apply`. The rootmoi config forwards it.

The carbon profile manages:

- Alacritty as the i3 terminal, with a shared `term` tmux session.
- greetd + tuigreet and the Xorg/i3 startup scripts. SDDM is disabled for the
  next login without stopping an existing graphical session.
- The internal eDP-1 panel: 1920x1200 at 60 Hz for the Linux console/greeter,
  2880x1800 at 60 Hz in i3. Firmware and GRUB display modes are separate.
- Backlight permissions for the video group and membership for the normal user.
- SUSTech official mirrors; the existing archlinuxcn setup uses SUSTech too.
- Tailscale, Pi, Codex, sing-box, Intel graphics and audio firmware packages;
  tailscaled and Bluetooth services. Tailscale account login remains manual.
- Hibernation boot arguments in `/etc/default/grub.d/90-carbon.cfg`. The device
  UUID and physical resume offset are read from `/swap/swapfile` whenever
  grub-mkconfig runs, rather than stored in Git. The hardware script regenerates
  grub.cfg after validating it; it never installs the bootloader or changes EFI
  boot entries.

Installation prerequisites stay outside chezmoi: the partitions, Btrfs subvolumes,
`fstab`, and the existing 16 GiB `/swap/swapfile` in `@swap`. Do not snapshot the
swap subvolume. Recreating or relocating the swapfile requires regenerating GRUB.
Disk UUIDs, passwords, EFI boot order and SSH host keys are not synchronized.
The sing-box JSON stays under `/etc/sing-box`; generate it separately using
`Documents/sb/devices/linux.js`, validate it, and then restart the service.
The profile only enables sing-box if that config already exists.

The earlier Ghostty/Cairo workaround is not needed by Alacritty and is not part
of the carbon profile. Existing encrypted user credentials continue to use the
repository's age mechanism; the decryption key remains local.
