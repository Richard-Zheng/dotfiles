# Arch Linux Dotfiles

## Machine profiles

The local chezmoi config uses two independent values:

- `type`: `desktop`, `laptop`, or `headless`
- `is_headless`: whether graphical desktop configuration should be excluded

`is_headless` defaults to `true` for the `headless` type and to `false` for the
other types. The default can be overridden during `chezmoi init`. Laptop-only
scripts are enabled only for `type = "laptop"`.

After pulling the profile migration on an existing machine, regenerate the
local config and choose the appropriate values. The generated config retains
the repository's age encryption settings:

```sh
chezmoi init
```

some optional AUR packages:

- `selectdefaultapplication-fork-git` - a utility to set default applications for MIME types and URL schemes in ~/.config/mimeapps.list
