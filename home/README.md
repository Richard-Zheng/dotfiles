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
