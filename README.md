# Arch Linux Dotfiles

## Fonts

```
sudo pacman -S noto-fonts-cjk ttf-fira-code ttf-fira-sans ttf-nerd-fonts-symbols ttf-twemoji
```

## zsh

```
sudo pacman -S zsh zsh-completions fzf
```

## Neovim

```
sudo pacman -S --needed neovim python-neovim git lazygit tree-sitter-cli curl xclip unzip base-devel fzf ripgrep fd
```

## i3

```
sudo pacman -S i3-wm rofi alacritty arandr keyd dunst acpi
paru -S i3blocks-git

sudo cp ~/.config/keyd/* /etc/keyd
```

