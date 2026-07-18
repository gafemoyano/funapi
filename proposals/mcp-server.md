# Proposal: `funapi mcp` — an MCP server for FunApi apps

Status: investigation (no implementation). Part of Phase 6 (Agentic Experience,
issue #10, Layer 1). This doc records what an MCP server would expose, the state
of the Ruby MCP ecosystem, and a go/no-go recommendation.

> Note on location: this lives at `proposals/` because the repo root `docs` is a
> bash script (the docs-site helper), not a directory.

## Problem

Phase 6's thesis is that FunApi is already agent-legible and AX just productizes
that. `llms.txt` / `llms-full.txt` (shipped this phase) give a coding agent the
*docs*. `funapi check` and `funapi routes --json` give it a *verification loop*.
The gap an MCP server closes is **live, structured introspection during a coding
session** — instead of the agent shelling out to `funapi routes --json` and
re-reading files, it can query the running project's shape and the docs through
one protocol the agent host already speaks (Claude Code, Cursor, Zed).

## What it would expose

An MCP server for a FunApi project would register three capabilities, all backed
by APIs that already exist in the gem:

1. **`docs_search` (tool)** — full-text search over the concatenated
   `llms-full.txt` content. The docs site already generates this document from
   `content/*.md`; the MCP server would index those same sources (BM25 or naive
   substring/section ranking is enough at this corpus size — ~107 KB). Returns
   matching sections with their canonical `/docs/...` URLs. This is the single
   highest-value capability: it turns "what's the SSE API?" into a grounded
   answer with a citation instead of a hallucinated one.

2. **`routes` / `schemas` (tools or resources)** — live introspection of the
   loaded app via the public API added this phase: `App#routes` (verb, path,
   tags, schema names), `App#schemas` (the distinct model/schema objects), and
   `Model#json_schema` for each. This is the same data `funapi routes --json`
   prints, exposed structurally so the agent can ask "does a POST /widgets route
   exist and what body does it validate?" without parsing a table.

3. **`openapi_diff` (tool)** — generate the current spec via `App#openapi_spec`
   and diff it against the committed `openapi.snapshot.json` (the same artifact
   `funapi check --update-snapshot` writes). Returns a structured added/removed/
   changed-operations diff — the introspective twin of `funapi check`'s
   spec-drift check, letting an agent see *what* changed, not just *that* it did.

Everything above is a thin adapter over code that already exists after this
phase's work. No new framework internals are required to build it.

## The Ruby MCP ecosystem

The official SDK exists and is credible:

- **`mcp` gem** — the official Ruby SDK, maintained by **Anthropic** under the
  `modelcontextprotocol` GitHub org (Apache-2.0, ~860 stars, ~780 commits, active
  changelog; latest release 0.24.0, July 2026). It handles JSON-RPC 2.0 framing,
  capability negotiation, and transports so we only write tool/resource classes.
- **Transports**: **stdio** (local CLI — the right fit for `funapi mcp`, which a
  coding-agent host launches as a subprocess) and **Streamable HTTP** (Rack-
  compatible, SSE for server→client). The HTTP transport keeps session state in
  memory, so it needs single-process or sticky sessions — irrelevant for the
  stdio use case.
- **Defining a tool** is a small class: a `description`, an `input_schema`, and a
  `self.call(**args, server_context:)` returning `MCP::Tool::Response`. This maps
  cleanly onto our three capabilities.
- Alternatives (`fast-mcp`, `ruby-llm-mcp`, `ruby-mcp-client`) exist but the
  official gem is the safe default; the client-side gems are not relevant here.

Maturity is sufficient to build on. The main caveat is version velocity (0.x,
protocol still evolving) — acceptable for an optional, non-core tool.

## Dependency & packaging concern

A hard project constraint is **no new runtime dependencies in the core gem**. The
`mcp` gem is a real dependency, so the MCP server must **not** be required by
`lib/funapi.rb`. Two viable shapes:

- **Optional subcommand** — `funapi mcp` lives in the CLI but `require "mcp"`
  lazily, failing with an actionable message ("add `gem \"mcp\"` to your
  Gemfile") if absent. Keeps one install, zero core-dependency cost.
- **Separate gem** — `funapi-mcp` depending on both `funapi` and `mcp`. Cleaner
  boundary, but more release overhead for a young feature.

Recommend the **optional subcommand** first; promote to a separate gem only if it
grows.

## Recommendation: GO (deferred), thin, optional

Build it, but not yet, and keep it thin. The value is real and the cost is low
because every backing API (`App#routes`, `App#schemas`, `App#openapi_spec`,
`Model#json_schema`, the `llms-full` corpus, the snapshot artifact) already
exists after this phase — the MCP server is an adapter, not new framework
surface. The right sequencing is to let `llms.txt` and `funapi check` prove
themselves in the AX eval harness (Layer 3) first; the eval is what tells us
whether live introspection actually moves first-try success or whether the static
docs + check loop already saturate it. If the eval shows agents still failing on
"does this route/schema exist" or "what changed in the spec" questions, that is
the signal to build `funapi mcp` as an optional, lazily-required stdio subcommand
wrapping the three capabilities above. Do not add `mcp` to the core gem's
dependencies under any packaging choice.
