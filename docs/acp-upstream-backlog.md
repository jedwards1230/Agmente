# ACP upstream backlog

Feature work we intend to run in the fork and, once proven, PR back to
`rebornix/Agmente`. See [`FORK.md`](FORK.md) → *Working on upstreamable
features* for the branch model and sequencing rules.

Each row is one self-contained PR on its own `main`-based branch, merged into
`fork` for daily use. Ordering follows the inbound-safe → wire-shape →
outbound-defer sequencing (outbound lifecycle methods wait for upstream's
connection-layer migration to settle).

## Inbound update / content (safe now — package-heavy, low conflict)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 1 | `feat/acp-usage-update` | Decode `usage_update` (context tokens + cost) → read-only badge | **built, local** |
| 2 | `feat/acp-session-info-update` | `session_info_update` → title/cwd/updatedAt (helps cwd-defaults-to-root) | todo |
| 3 | `feat/acp-plan-render` | Render `plan` on the ACP path (today only Codex renders plans) | todo |
| 4 | `feat/acp-content-blocks` | Decode non-text `ContentBlock`s + tool-call `diff`/content (dropped today) | todo |

## Wire-shape conformance (package-only)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 5 | `feat/acp-session-methods-v1` | Align `session/list` + `resume` + `set_config_option` to the stable ACP v1 shapes | todo (scope first — may split) |

## Outbound lifecycle (deferred until upstream's view-model migration settles)

| # | Scope |
| - | ----- |
| — | `session/close`, `logout`, `session/delete` — call sites live in the churny `AppViewModel`/`ServerViewModel` layer |

## Notes

- **Schema source of truth:** the v1 machine schema at
  `github.com/agentclientprotocol/agent-client-protocol` (`schema/v1/schema.json`).
  Confirm a variant is *stable* (no `unstable` marker) before building on it —
  `usage_update` is stable; verify each new one.
- **Verify locally:** `cd ACPClient && swift test` covers the package layer.
  The full app + `AgmenteTests` build needs the iOS 26 simulator (Xcode 26),
  which CI runs; a local machine without that runtime can only test the package.
