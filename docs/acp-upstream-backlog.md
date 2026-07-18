# ACP client backlog — M5 featureset expansion

The fork's next milestone is a cross-repo **M5 — ACP v1 Featureset Expansion**:
the agent-sdk-go models the wire types, gofer emits them, and Agmente decodes
and renders them. This doc is Agmente's **client (decode/render) leg** of that
milestone. Ecosystem work (MCP-over-ACP, subagents, skills, plugins) is **M6**;
auto-config / import / mDNS discovery is **M7**.

The reference is the wiki **ACP Conformance Matrix**:
<https://wiki.lilbro.cloud/home/projects/acp-conformance-matrix.md>.

Each row is one self-contained PR on its own `main`-based branch, merged into
`fork` for daily use. See [`FORK.md`](FORK.md) → *Working on upstreamable
features* for the branch model and inbound-safe → wire-shape → outbound-defer
sequencing.

## Governing policies

- **Spec-general only (hard constraint).** Agmente decodes the **standard ACP
  `session/update` surface** and nothing else. Never couple the decode path to
  gofer-proprietary frames (e.g. `gofer/event`) — the daemon is one of many ACP
  servers and Agmente is one of many ACP clients (see [`FORK.md`](FORK.md) →
  *One client of many*).
- **Promote-if-stable.** Build a capability on the standard ACP surface when a
  **stable** spec variant exists; fall back to a gofer-native endpoint only when
  the spec surface is unstable or absent. Confirm *stable* (no `unstable`
  marker) against the v1 machine schema before building on it.
- **Model discovery.** The `session/new` model picker is fed by gofer's
  **native list-models** endpoint, *not* the unstable `providers/list`.

## Inbound update / content (safe now — package-heavy, low conflict)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 1 | `feat/acp-usage-update` | Decode `usage_update` (context tokens + cost) → read-only badge | **done** — merged to `fork`; wire side landed (SDK v0.6.0 + gofer #97), live end-to-end |
| 2 | `feat/acp-session-info-update` | `session_info_update` → live session title/updatedAt | **done** — merged to `fork` |
| 3 | `feat/acp-plan-render` | Render `plan` on the ACP path (today only Codex renders plans) | todo |
| 4 | `feat/acp-content-blocks` | Decode non-text `ContentBlock`s (`image`/`audio`/`resource`) + tool-call `diff` (red/green edit view), dropped today | ready when a producer emits (see note) |

## Wire-shape conformance (package-only)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 5 | `feat/acp-session-methods-v1` | Align `session/list`, `resume`, `set_config_option`, and **`cwd`** to the stable ACP v1 shapes | todo (scope first — may split) |

## Model picker (gofer-native)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 6 | `feat/acp-model-picker` | Feed the `session/new` model picker from gofer's native **list-models** endpoint (not `providers/list`) | todo |

## Outbound lifecycle (deferred until upstream's view-model migration settles)

| # | Scope |
| - | ----- |
| — | `session/close`, `logout`, `session/delete` — call sites live in the churny `AppViewModel`/`ServerViewModel` layer |

## Notes

- **#4 is not blocked on Agmente.** `image`/`audio`/`resource` content and
  tool-call `diff` are already modeled upstream/SDK-side and pass through gofer,
  but no producer emits them yet. Scope #4 as *ready to decode when a producer
  emits*, not as blocked work.
- **`cwd` source.** `cwd` is delivered on `session/list`'s `SessionInfo` — it is
  **not** carried by `session_info_update` (#2). It lands with the session
  methods in #5, which is why the cwd-defaults-to-root fix rides there.
- **Schema source of truth:** the v1 machine schema at
  `github.com/agentclientprotocol/agent-client-protocol` (`schema/v1/schema.json`).
  `usage_update` is stable; verify each new variant.
- **Verify locally:** `cd ACPClient && swift test` covers the package layer.
  The full app + `AgmenteTests` build needs the iOS 26 simulator (Xcode 26),
  which CI runs; a local machine without that runtime can only test the package.
