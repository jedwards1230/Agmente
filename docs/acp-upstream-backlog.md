# ACP client backlog — M5 featureset expansion

The cross-repo **M5 — ACP v1 Featureset Expansion** milestone (the agent-sdk-go
models the wire types, gofer emits them, and Agmente decodes and renders them)
is **complete as of 2026-07-25**: every committed slice is live end-to-end
across all three repos, and Agmente's client leg — this doc — is done. Ecosystem
work (MCP-over-ACP, subagents, skills, plugins) is **M6**, and is next;
auto-config / import / mDNS discovery is **M7**.

> **Milestone numbering is per-repo.** Agmente's M6/M7 above are *this repo's*
> stages. The same ecosystem work is **gofer's M7** and the same wire modeling
> was **agent-sdk-go's M4** — each repo numbers from what shipped in it. Don't
> reconcile the numbers across repos; match on the work, not the label.

The reference is an internal ACP v1 conformance matrix (spec ↔ SDK ↔ gofer ↔ Agmente).

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
| 2 | `feat/acp-session-info-update` | `session_info_update` → live session title/updatedAt | **done** — merged to `fork` (`933b440`) |
| 2a | `feat/acp-config-option-update` | Apply inbound `config_option_update` (push agent-side model changes into the picker) | **done** — merged to `fork` (`0cef925`, #14); gofer emits it (agent-sdk-go v0.10.0) |
| 3 | `feat/acp-plan-render` | Render `plan` on the ACP path (today only Codex renders plans) | **done** — merged to `fork` (`91c2a57`, #13); gofer emits `plan` (agent-sdk-go v0.9.0) |
| 4 | `feat/acp-content-blocks` | Decode non-text `ContentBlock`s (`image`/`audio`/`resource`) + tool-call `diff` (red/green edit view) | **`diff` done** — merged to `fork` (`f15482a`, #10), live end-to-end (SDK v0.7.0 emits it from the edit/write tools). `image`/`audio`/`resource` still have **no producer anywhere** — see note |

## Wire-shape conformance (package-only)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 5 | `feat/acp-session-methods-v1` | Align `session/list`, `resume`, `set_config_option`, and **`cwd`** to the stable ACP v1 shapes | **done** — merged to `fork` via `ab9b267` (#12). `ACPService.listSessions`/`loadSession`/`resumeSession`, the `resumeSession`/`listSessions`/`sessionListRequiresCwd` capability flags on `AgentInfo`, and `cwd` on `SessionSummary` are all in the package |

## Model picker (gofer-native)

| # | Branch | Scope | Status |
| - | ------ | ----- | ------ |
| 6 | `feat/acp-model-picker` | Feed the model picker from gofer's native **`gofer/models`** endpoint (not `providers/list`) | **done** — merged to `fork`. Discovery is gofer-native (`ACPService.listGoferModels` → `GoferModelsParser`); if the agent doesn't answer `gofer/models` the picker hides (graceful degradation). Applying a model uses the spec method `session/set_config_option` (`configId: "model"`), never a native set. |

## Outbound lifecycle (deferred until upstream's view-model migration settles)

| # | Scope |
| - | ----- |
| — | `session/close`, `logout`, `session/delete` — call sites live in the churny `AppViewModel`/`ServerViewModel` layer |

## Notes

- **#4, updated.** The `diff` half is **done and live** — agent-sdk-go v0.7.0
  emits a structured `diff` block from the edit/write tools, gofer passes it
  through, and Agmente renders it. `image`/`audio`/`resource` remain modeled
  with **no producer in any of the three repos**, because no builtin tool
  naturally emits them (`terminal` likewise). Treat those three as **descoped
  from M5**, not as pending Agmente work — there is nothing to decode until
  some tool produces one.
- **`cwd` source.** `cwd` is delivered on `session/list`'s `SessionInfo` — it is
  **not** carried by `session_info_update` (#2). It landed with the session
  methods in #5, which is why the cwd-defaults-to-root fix rode there.
- **Schema source of truth:** the v1 machine schema at
  `github.com/agentclientprotocol/agent-client-protocol` (`schema/v1/schema.json`).
  `usage_update` is stable; verify each new variant.
- **Verify locally:** `cd ACPClient && swift test` covers the package layer.
  The full app + `AgmenteTests` build needs the iOS 26 simulator (Xcode 26),
  which CI runs; a local machine without that runtime can only test the package.
