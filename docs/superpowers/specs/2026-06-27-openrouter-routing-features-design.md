# Design: OpenRouter Routing & Delegation Features

**Date:** 2026-06-27
**Gem:** `open_router_enhanced`
**Target version:** 2.2.0
**Status:** Approved — ready for implementation plan

## Goal

Add first-class, validated, ergonomic access to three OpenRouter platform features
that currently must be hand-rolled as raw `plugins:`/`tools:` hashes:

1. **Fusion** (`openrouter/fusion`) — fan a prompt out to a panel of models in
   parallel and synthesize one answer via a judge model.
2. **Subagent server tool** (`openrouter:subagent`) — let an orchestrator model
   delegate self-contained subtasks mid-generation to a cheaper worker model.
3. **Pareto Code Router** (`openrouter/pareto-code`) — set `min_coding_score` and
   route to the cheapest code-capable model clearing that bar.

These features are **still evolving on OpenRouter's side**. The goal is reliable
*access and use* with solid error handling — not a comprehensive DSL. A richer DSL
may follow later; this design deliberately keeps the surface small and additive.

## Non-goals (v1 / YAGNI)

- No fluent/builder DSL (a hybrid helper+options surface was chosen; DSL may come later).
- No special streaming handling — these flow through `complete`'s existing `stream:`
  param as pass-through, not specially tested in v1.
- No automatic fusion cost-guardrail. Fusion costs ~4–5× a single completion; this is
  documented, and the existing `:after_response` callback already lets callers meter spend.
- No typed parsing of the Fusion judge's internal JSON (consensus/contradictions/etc.) —
  OpenRouter does not publish a stable caller-facing schema for it.

## Architecture

The gem already serializes all three features correctly through existing plumbing
(`CompletionOptions` → `ParameterBuilder#prepare_base_parameters` → `plugins`/`tools`/
`model`). Nothing in `complete()`'s core flow changes. The work is a thin ergonomic +
validation layer, mirroring how `smart_complete` wraps `complete`.

Two new units + a minimal response surface:

### 1. `OpenRouter::Routing` (mixin, included in `Client`)

File: `lib/open_router/routing.rb`. Included in `Client` alongside the existing mixins.

```ruby
FUSION_MODEL      = "openrouter/fusion"
PARETO_CODE_MODEL = "openrouter/pareto-code"

# Fusion
def fuse(messages, analysis_models: nil, judge: nil, preset: nil,
         max_tool_calls: nil, **opts)
  # validate, build plugin hash (compact), delegate to complete
  # model: FUSION_MODEL, plugins: [{ id: "fusion", ... }.compact]
end

# Pareto code router
def pareto_complete(messages, min_coding_score: nil, **opts)
  # validate, build plugin, delegate
  # model: PARETO_CODE_MODEL, plugins: [{ id: "pareto-router", min_coding_score: }.compact]
end
```

- Both accept the full `**opts` / `CompletionOptions` surface, so `temperature:`,
  `session_id:`, callbacks, etc. compose normally.
- If a caller passes a `plugins:` of their own, the fusion/pareto plugin is **merged**
  into it (not clobbered), de-duped by `id`.

**Validation (fail-fast, raises `ArgumentError`):**
- `analysis_models`: array of 1–8 model id strings when present.
- `max_tool_calls`: integer 1–16 when present.
- `min_coding_score`: numeric 0.0–1.0 when present.
- `judge`/`preset`: passed through as strings/symbols; no hard validation (server-side,
  in flux).

### 2. `OpenRouter::SubagentTool < OpenRouter::Tool`

File: `lib/open_router/subagent_tool.rb`. Subclasses `Tool` so it passes the existing
`serialize_tools` `when Tool` branch, but overrides construction/validation/`to_h` to
emit the server-tool shape instead of the `function` shape:

```ruby
sub = OpenRouter::SubagentTool.new(
  model: "z-ai/glm-5.2",            # required; pins the worker model
  instructions: "Be concise.",      # optional
  max_completion_tokens: 1024,      # optional
  temperature: 0.2,                 # optional
  reasoning: { effort: "low" })     # optional

sub.to_h
# => { type: "openrouter:subagent",
#      parameters: { model:, instructions:, max_completion_tokens:, temperature:, reasoning: }.compact }
```

- `model:` is **required** → `ArgumentError` if missing/blank.
- Used via the normal path: `client.complete(messages, model: orchestrator, tools: [sub])`.
- `serialize_tools` needs no change if `SubagentTool` is a `Tool` subclass; we will add a
  focused spec asserting it serializes correctly through `complete`.

### 3. Response surface (minimal, cassette-driven)

Small additions to `Response` (`lib/open_router/response.rb`):

- `selected_model` — the concrete model the router actually resolved, read from the
  response `model` field. Useful for pareto / auto / fusion ("which model answered?").
- `router` and any subagent-delegation metadata — added **only if** the first real
  cassette shows the API returns them. We do not invent fields the live API doesn't emit.

## Error handling (explicit requirement)

Because these endpoints are in flux, error paths are first-class and tested:

- **Client-side validation errors** raise `ArgumentError` *before* any HTTP call
  (bad `min_coding_score`, empty/oversized `analysis_models`, missing subagent `model`).
- **API rejections** (e.g. a 400 when a plugin field name has drifted server-side) surface
  through the gem's existing `ServerError`/error handling and `:on_error` callback,
  unchanged. We add a VCR spec that records a real error response (e.g. an invalid
  `min_coding_score` or malformed plugin) and asserts the gem raises/propagates cleanly
  rather than returning a malformed `Response`.
- **Subagent runtime errors**: the server tool may return
  `{ "status": "error", "task_name": ..., "error": ... }`. The orchestrator's final
  message still returns normally; we assert the completion succeeds and document that
  per-delegation errors are surfaced in the model's own output (not raised), since the
  server tool runs server-side.
- **Fusion partial-panel failure**: documented as handled by OpenRouter server-side
  (judge synthesizes from whoever succeeded); no special client handling. Covered by the
  happy-path cassette returning a synthesized answer.

## Testing strategy (TDD, red → green, per feature)

For **each** feature, two layers:

**(a) Unit / contract spec** (mocks `post`, asserts the exact `parameters:` hash built) —
the "internal public method spec," modeled on the existing `#complete` spec in
`spec/open_router_spec.rb`:
- `spec/routing_spec.rb` — `fuse` and `pareto_complete` build correct params; validation
  raises on bad input; plugins merge rather than clobber.
- `spec/subagent_tool_spec.rb` — `SubagentTool#to_h` shape; required-model validation;
  serializes correctly when passed to `complete` (mocked `post`).

**(b) VCR integration spec** (real cassette against the live API):
- `spec/vcr/fusion_spec.rb`, `spec/vcr/pareto_spec.rb`, `spec/vcr/subagent_spec.rb`
- One happy-path cassette each + at least one **error cassette** (e.g. invalid score / bad
  plugin field) to lock real error behavior.
- Recorded with `VCR_RECORD_NEW=1` (never delete-and-rerecord — per project memory on the
  shared mutable on-disk model cache).
- **Use cheap models** for all recordings (e.g. budget panel members and a budget judge for
  fusion; a cheap worker for subagent). Never the most expensive frontier models.

The integration record run is the source of truth that pins the doc-flagged uncertain
field names (`analysis_models` vs `models`, `min_coding_score` placement, subagent result
payload shape). If the live API disagrees with the docs, the unit spec's expected hash is
corrected to match reality — the cassette wins.

## Files touched

New:
- `lib/open_router/routing.rb`
- `lib/open_router/subagent_tool.rb`
- `spec/routing_spec.rb`, `spec/subagent_tool_spec.rb`
- `spec/vcr/fusion_spec.rb`, `spec/vcr/pareto_spec.rb`, `spec/vcr/subagent_spec.rb`
- new cassettes under `spec/fixtures/vcr_cassettes/`

Modified:
- `lib/open_router/client.rb` — `require_relative` + `include OpenRouter::Routing`
- `lib/open_router/response.rb` — `selected_model` (+ cassette-driven extras)
- `lib/open_router.rb` — `require` the new files if not autoloaded
- `lib/open_router/version.rb` — bump to 2.2.0
- docs (README / feature docs) — usage + cost notes (after green)

## Acceptance criteria

- `fuse`, `pareto_complete`, and `SubagentTool` work end-to-end against real recorded
  cassettes using cheap models.
- Unit specs assert exact request shapes and validation behavior.
- Error paths (validation + real API error) are tested and behave predictably.
- Full suite green in CI (`:none` record mode replays cassettes).
- Version bumped to 2.2.0; docs updated.
