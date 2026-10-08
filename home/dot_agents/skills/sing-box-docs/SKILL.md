---
name: sing-box-docs
description: >-
  Fetches up-to-date sing-box documentation (sing-box.sagernet.org). Use
  whenever working with sing-box, its JSON configuration (inbounds, outbounds,
  DNS, route rules, endpoints, services), proxy protocols (VLESS, Hysteria2,
  TUIC, AnyTLS, ShadowTLS, Trojan...), or the `sing-box` CLI. The docs are
  MkDocs Material built from the `docs/` directory of the SagerNet/sing-box
  repo on the `testing` branch; fetch raw markdown from GitHub. The site has
  no llms.txt and does not serve .md.
---

# sing-box docs

The docs at sing-box.sagernet.org are built with MkDocs Material from the
`docs/` directory of the [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
repo. The source lives on the `testing` branch (the repo's default branch).

The rendered site serves HTML only — there is no `llms.txt`, and appending
`.md` to a page URL returns 404. Fetch the **raw markdown from GitHub** instead.

## Fetch a page

```bash
# pattern
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/testing/docs/<path>.md

# examples
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/testing/docs/index.md
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/testing/docs/configuration/outbound/vless.md
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/testing/docs/configuration/dns/server/fakeip.md
```

Paths mirror the site URLs:
`https://sing-box.sagernet.org/configuration/outbound/vless/`
→ `docs/configuration/outbound/vless.md`.

Chinese translations use a `.zh.md` suffix, e.g.
`docs/configuration/outbound/vless.zh.md`.

## Version-specific docs

Docs are versioned by git tag. Swap `testing` for a release tag (`vX.Y.Z`)
in the raw URL:

```bash
# docs for a specific release
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/v1.14.1/docs/configuration/outbound/vless.md

# which tag matches the installed binary
sing-box version          # e.g. "sing-box version 1.14.1" -> tag v1.14.1

# list recent tags
git ls-remote --tags --sort=-v:refname https://github.com/SagerNet/sing-box.git \
  | grep -v '\^{}' | head
```

Use `testing` for the latest development docs, or a tag to match a specific
released version. The rendered site has no per-version URLs — only the tag-based
raw GitHub URLs give you an exact version.

## Page index / navigation

The nav tree is `mkdocs.yml`:

```bash
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/testing/mkdocs.yml
```

Its `nav:` section lists every page in order (Home, Installation, Graphical
Clients, Manual, Configuration → Inbound/Outbound/DNS/Route/Rule Set/Endpoint/
Service/Shared/Experimental, ...).

## Search across all docs

The built site exposes the MkDocs search index — every page's title and text in
one JSON file (~1.4 MB):

```bash
# find pages matching a path fragment
curl -s https://sing-box.sagernet.org/search/search_index.json \
  | jq -r '.docs[] | select(.location|test("outbound/vless")) | .location'

# grep page text for a term
curl -s https://sing-box.sagernet.org/search/search_index.json \
  | jq -r '.docs[] | select(.text|test("FakeIP"; "i")) | .location' | head
```

`sitemap.xml` also lists every page URL.

## Bulk queries: temporary shallow clone

If you need to read or grep many pages, a throwaway shallow clone is cheaper
than many raw fetches, and keeps the full source tree around for reference.
Use a temp dir so it never pollutes the user's repos:

```bash
# shallow clone of the default branch (testing), ~15 MB, a few seconds
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/SagerNet/sing-box.git "$tmp/sing-box"
rg -n 'FakeIP' "$tmp/sing-box/docs"        # grep everything locally
rm -rf "$tmp"                               # clean up when done
```

`testing` is the default branch, so no `--branch` is needed. To pin a released
version, pass a tag instead:

```bash
git clone --depth 1 --branch v1.14.1 \
  https://github.com/SagerNet/sing-box.git "$tmp/sing-box-v1.14.1"
```

## Notes

- Site is public and unauthenticated; fetch freely.
- `.md` works on GitHub raw but NOT on the rendered site.
- Page paths are case-insensitive and match the URL path.
