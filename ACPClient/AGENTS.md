# ACPClient Package Guide

## Scope
Typed ACP transport/service package used by the iOS app.

## External Repo Paths
- Read `.agmente.paths` (from repo root) before cross-checking ACP upstream docs/spec.
- ACP upstream reference root: `AGMENTE_ACP_REPO/docs`.

## Architecture Model
- Transport concerns, request orchestration, and ACP parsing are separated layers.
- Public service APIs should remain typed and hide wire-format details from callers.
- Parsing helpers should be resilient to optional/partial ACP payloads.

## Extension Pattern
When adding ACP method support:
1. Add the method constant and typed payload mapping.
2. Expose a typed service wrapper.
3. Add response/event parsing coverage.
4. Ensure delegate and pending-request behavior remain correct.
5. Add package tests for success and failure paths.

## gofer-native methods
- Non-spec, gofer-only JSON-RPC methods live in `GoferMethods` (kept apart from
  `ACPMethods`). Today: `gofer/models` (model discovery → `ACPService.listGoferModels`
  / `GoferModelsParser`). Only use these where the caller degrades gracefully when
  the agent doesn't implement them — a thrown RPC error means "unsupported".
- Never apply state via a gofer-native method when a spec method exists: model
  selection is applied over spec `session/set_config_option` (`configId: "model"`).

## Compatibility Rules
- Preserve support for server-initiated JSON-RPC requests (do not treat as transport errors).
- Keep slash-escaping compatibility option functional.
- Keep request ID/pending continuation behavior deterministic.
- Keep reconnection/disconnect semantics from breaking in-flight request handling.

## Tests
- Run package tests for `ACPClient`.
