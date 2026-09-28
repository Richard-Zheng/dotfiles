---
name: lazyvim-docs
description: >-
  Answers LazyVim and Neovim configuration questions from a local offline
  snapshot of lazyvim.org at ~/.agents/knowledge/lazyvim. Use whenever working
  with LazyVim, its starter config (~/.config/nvim), lua/plugins specs,
  :LazyExtras, keymaps, LSP/formatting/treesitter options, or any plugin in the
  extras catalog. Read the local files first — no network needed. The snapshot
  is a copy of the docs/ directory of LazyVim/lazyvim.github.io@main.
---

# LazyVim docs

A complete offline copy of <https://lazyvim.org> lives at
`~/.agents/knowledge/lazyvim/` (138 markdown files). Read it directly; do not
crawl the web for LazyVim questions.

The rendered site is Docusaurus v2: there is **no `llms.txt`** and the site does
**not** serve `.md`. The local snapshot is the practical way to read it.

## Layout

Paths mirror the site URLs:

| Site URL | Local file |
|---|---|
| `/` (intro) | `intro.md` |
| `/installation` | `installation.md` |
| `/keymaps` | `keymaps.md` |
| `/news` | `news.md` |
| `/configuration/<page>` | `configuration/<page>.md` |
| `/plugins/<page>` | `plugins/<page>.md` |
| `/extras/<category>/<extra>` | `extras/<category>/<extra>.md` |

- `configuration/` — general settings, keymaps, lazy.nvim, plugins, recipes, tips.
- `plugins/` — the core (default-enabled) plugin sets: coding, colorscheme,
  editor, formatting, linting, lsp, treesitter, ui, util.
- `extras/` — the `:LazyExtras` catalog, one file per extra. Categories: `ai`,
  `coding`, `dap`, `editor`, `formatting`, `lang`, `linting`, `lsp`, `test`,
  `ui`, `util`.
- `_category_.yml` files are Docusaurus sidebar metadata — ignore them.

## Recipes

```bash
K=~/.agents/knowledge/lazyvim

# read a page
cat "$K/configuration/keymaps.md"

# find which extra enables a plugin, e.g. blink.cmp
rg -l 'blink' "$K/extras"

# search everything for a setting or keymap
rg -n 'scrolloff' "$K"
rg -n 'LazyExtras|:Lazy ' "$K/configuration"

# every extra in a category
ls "$K/extras/lang"
```

`keymaps.md` is the full default keymap table (~39 KB) — grep it instead of
reading it whole.

## Match the installed version

The snapshot tracks upstream `main`. A user's LazyVim may lag behind, so when a
default differs, check the local LazyVim checkout:

```bash
git -C ~/.local/share/nvim/lazy/LazyVim log -1 --format='%h %cs'
```

To read the docs at that exact commit, fetch from GitHub raw (only when the
snapshot is wrong for their version):

```bash
curl -s https://raw.githubusercontent.com/LazyVim/lazyvim.github.io/<commit>/docs/configuration/keymaps.md
```

## Refresh the snapshot

Update `~/.agents/knowledge/lazyvim` from upstream (run from anywhere):

```bash
tmp=$(mktemp -d)
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/LazyVim/lazyvim.github.io.git "$tmp/docs"
git -C "$tmp/docs" sparse-checkout set docs
rm -rf ~/.agents/knowledge/lazyvim
cp -r "$tmp/docs/docs" ~/.agents/knowledge/lazyvim
git -C "$tmp/docs" log -1 --format='synced %h %cs'
rm -rf "$tmp"
```

`docs/` is the only directory needed. The site source repo is
`LazyVim/lazyvim.github.io` on branch `main` — **not** `LazyVim/LazyVim`,
which is the plugin itself and has no `docs/` tree.

After refreshing, re-apply chezmoi so the managed copy stays in sync:

```bash
chezmoi re-add ~/.agents/knowledge
```

## Notes

- The snapshot is offline and public; no auth or network needed to read it.
- Page paths are case-insensitive and match the URL path.
- `intro.md` etc. start with Docusaurus frontmatter (`slug`, `sidebar_position`)
  and may contain `import`/`<Tabs>` JSX from the site build — read the prose,
  ignore the JSX.
