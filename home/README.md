# Dotfiles

Managed with [chezmoi](https://chezmoi.io). The repository holds **two** chezmoi
sources plus per-machine flag files in one git tree:

```text
hosts/  -> per-machine flag files (`<hostname>.toml`), loaded into ~/.config/chezmoi/chezmoi.toml
home/   -> ~        (user dotfiles, applied by the normal `chezmoi` run)
root/   -> /        (system files, applied as root by `rootmoi`)
```

The `home/` split is signalled by [`.chezmoiroot`](https://www.chezmoi.io/reference/special-files/chezmoiroot/),
which points the user-level instance at `home/`.

## Per-machine `chezmoi.toml` (`hosts/*.toml`)

Every machine has its own explicit, fine-grained TOML config under `hosts/`:

- `hosts/thinkarch.toml` — ThinkBook 14 G6+ AHP (Arch Linux laptop, greetd + ghostty, btrfs `/btrfs/@home`)
- `hosts/vccarch.toml` — Daily workstation (Arch Linux desktop, greetd + ghostty, dual 4K `HDMI-1` + `DP-1`)
- `hosts/zzzlab.toml` — Homelab Proxmox VE VM (Ubuntu 26.04, headless minimal CLI/shell/tmux/nvim)
- `hosts/default.toml` — Headless fallback used in CI, containers, and unknown hosts

On `chezmoi init`, `home/.chezmoi.toml.tmpl` matches `hosts/<hostname>.toml`
automatically (or honors `CHEZMOI_HOST=<name>`, or prompts interactively on an
unknown host) and writes the full flag set into `~/.config/chezmoi/chezmoi.toml`.
Every template and `.chezmoiignore` reads only these flags — never hostnames.

### Adding a new machine

```sh
cp hosts/thinkarch.toml hosts/<new-hostname>.toml
# edit flags in hosts/<new-hostname>.toml
chezmoi init --apply
```

### Updating flags on an existing machine

Edit `hosts/<hostname>.toml` and regenerate `~/.config/chezmoi/chezmoi.toml`:

```sh
chezmoi init && chezmoi apply
```

For quick local experiments, you can also edit `~/.config/chezmoi/chezmoi.toml`
directly and run `chezmoi apply`.

### Migrating a machine from the old `chezmoi.yaml`

Remove `~/.config/chezmoi/chezmoi.yaml` (or run `chezmoi apply`, which deletes
it via `run_before_10-migrate.sh` and exits with instructions), then run:

```sh
chezmoi init --source ~/.local/share/chezmoi && chezmoi apply --force
```

## Flag groups in `chezmoi.toml`

- `[data.desktop]`: `enabled`, `display_manager` (`greetd`/`sddm`/`none`), `terminal` (`ghostty`/`alacritty`/empty), `fcitx5`, `keyd`
- `[data.display]`: `i3_xrandr_cmd`, `sensor_chip`, `dual_monitor`, `hdmi_output`, `dp_output`, `resolution`, `hdmi_rate`, `dp_rate`
- `[data.hardware]`: `laptop`, `backlight_udev`, `bluetooth`, `gpu_packages`
- `[data.boot]`: `grub_cmdline_video`, `grub_swapfile_hibernation`
- `[data.storage]`: `btrbk_proj_snapshots`
- `[data.system]`: `arch_sustech_mirror`, `archlinuxcn`, `ntp_timesyncd`
- `[data.tools]`: `tailscale`, `sing_box`, `ai_cli`, `aliyun_dns`, `uv`
- `[data.platform]` *(auto-detected)*: `is_linux`, `is_mac`, `is_arch`, `is_debian`, `is_container`, `host_file`, `host_config_sha256`

## rootmoi

`root/` is applied by a second chezmoi instance that runs as root with
`destDir = "/"`. It is invoked through `~/.local/bin/rootmoi` using
`~/.config/rootmoi/chezmoi.toml` (generated automatically from your user
`chezmoi.toml` data). After every `chezmoi apply`,
`home/.chezmoiscripts/run_after_20-run-rootmoi.sh.tmpl` runs `rootmoi apply`
automatically. Set `NO_ROOTMOI=1` to skip it.

System files are declared under `root/etc/...` and `root/usr/...`. Package-owned
files like `/etc/environment` are merged with `modify_` templates instead of
being replaced wholesale.

## Snapshots of `~/proj`

When `storage.btrbk_proj_snapshots = true` (and `/btrfs/@home` is mounted on a
btrfs filesystem), `~/proj` is created as a btrfs subvolume and snapshotted by
[btrbk](https://digint.ch/btrbk/) (`root/etc/btrbk/btrbk.conf.tmpl`) every
minute on change, preserving the last hour in full plus the first snapshot of
each of the last 10 hours in `~/.proj-snapshots`.

## Verification

Validate all `hosts/*.toml` profiles locally (no root or Docker required):

```sh
scripts/check-hosts.sh
```

Full container smoke test:

```sh
scripts/test.sh --os archlinux
scripts/test.sh --os ubuntu-26.04
```

## Notes on host prerequisites

Disk partitions, Btrfs subvolumes, `fstab`, swapfiles (`/swap/swapfile`), disk
UUIDs, passwords, EFI boot entries, SSH host keys, the age key
(`~/.config/chezmoi/key.txt`), Tailscale login, and `/etc/sing-box/config.json`
remain outside chezmoi. `sing-box.service` is only enabled when
`/etc/sing-box/config.json` already exists.
