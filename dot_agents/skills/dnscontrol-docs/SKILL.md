---
name: dnscontrol-docs
description: >-
  Fetches up-to-date DNSControl documentation (docs.dnscontrol.org). Use
  whenever working with DNSControl, dnsconfig.js, DNS providers, domain
  modifiers, SPF/DMARC records, or `dnscontrol` CLI commands. The docs are
  GitBook-hosted and expose plain markdown; fetch them with curl — there is no
  need for the GitBook MCP endpoint or any wrapper script.
---

# DNSControl docs

The docs at docs.dnscontrol.org are GitBook-hosted and expose plain text.
Fetch them with `curl` — there is no need for the MCP endpoint
(`/~gitbook/mcp`) or any wrapper script.

## Recipes

```bash
# Index of every page: "- [Title](url)" lines
curl -s https://docs.dnscontrol.org/llms.txt

# Any page as raw markdown — just append .md to its URL
curl -s https://docs.dnscontrol.org/provider/cloudflareapi.md
curl -s https://docs.dnscontrol.org/language-reference/domain-modifiers/spf_builder.md

# Everything at once (concatenated markdown, paginated)
curl -s https://docs.dnscontrol.org/llms-full.txt
```

`llms-full.txt` is large (~1 MB total). Prefer fetching a single `.md` page
when you already know the path; use the full dump only for broad searches.

Each part's header states its position (e.g. `part 1 of N`, `pages X–Y of Z`)
and links to the next part, so read that header rather than assuming a fixed
number of pages.

## Search

Grep the full dump. Each page starts with a `# Title` heading, so once you
have a hit you can locate the surrounding page heading with a wider context:

```bash
curl -s https://docs.dnscontrol.org/llms-full.txt \
  | grep -i -n -A3 'spf.*flatten'
```

Or narrow to one page up front and fetch just that `.md` file.

To find a page by name first, grep the index:

```bash
curl -s https://docs.dnscontrol.org/llms.txt | grep -i cloudflare
```

## Notes

- Paths are case-insensitive and match the URL path, e.g. `provider/bind`,
  `commands/init`, `language-reference/domain-modifiers/mx`.
- Titles in `llms.txt` escape underscores (`SPF\_BUILDER`); the URL does not
  (`.../spf_builder.md`).
- These are public, unauthenticated, and safe to fetch freely.
