---
title: CLI & Dev Server
---

# CLI & Dev Server

FunApi ships a command-line tool (`funapi`) built on the Ruby standard library —
no extra runtime dependencies.

```bash
funapi new NAME              # scaffold a new application
funapi dev [--port] [--bind] # run under Falcon with code reloading
funapi routes [--json]       # print the route table
funapi check [--json]        # verify boot, schemas, OpenAPI, and spec drift
funapi version
```

## funapi new

Scaffolds a ready-to-run project: `app.rb` (models + routes), `config.ru`, a
`Gemfile` (funapi + falcon, with a commented Sequel/pg block), an `AGENTS.md`
for AI coding agents, a `test/` directory using `FunApi::TestClient`, plus
`README.md` and `.gitignore`. It refuses to overwrite a non-empty directory.

The scaffold exposes the app as an `Application` constant so `config.ru`,
`funapi dev`, and your tests can all reach the same object.

## funapi dev

Boots `app.rb`/`config.ru` under Falcon in development mode and prints the
`/docs` URL:

```bash
$ funapi dev --port 3000
FunApi dev server: http://localhost:3000
Interactive docs:  http://localhost:3000/docs
Code reloading:    on (restarts on file change)
```

Options: `--port` (default 3000), `--bind` (default `localhost`),
`--no-reload` to disable the file watcher.

### How code reloading works

Reloading is a **full process restart**, not in-place code swapping. A
background thread polls file modification times in the project directory; on a
change it `exec`s a fresh `funapi dev` process in place.

This is a deliberate choice for an async framework. Falcon runs your handlers as
fibers on a shared reactor; unloading and re-requiring code mid-flight would
leave stale fibers, dangling constants, and half-open connections. A clean
process restart guarantees every request runs against exactly the code on disk —
correctness over shaving milliseconds.

**Constraints, honestly:**

- A change triggers a **full restart**: in-flight requests are dropped and
  startup runs again (`on_startup` hooks re-run, connection pools rebuild).
  Restarts take as long as your app's boot.
- Detection is **mtime polling** (~1s interval), not OS file events. There is no
  new dependency, but changes are picked up within about a second, not
  instantly.
- `vendor/`, `.git/`, `tmp/`, `node_modules/`, `.bundle/`, `log/`, and
  `coverage/` are ignored. Only `.rb` and `.ru` files are watched.
- Reloading is **development-only**. In production, run under Falcon (or any
  Rack 3 server) directly — see [Deployment](/docs/patterns/deployment).

## funapi routes

Prints the route table — verb, path, tags, and which schemas each route
declares:

```bash
$ funapi routes
VERB  PATH          TAGS  SCHEMAS
GET   /                   -
POST  /widgets            body=CreateWidget response=Widget
```

`--json` emits machine-readable output, handy for tooling and AI agents:

```bash
funapi routes --json
```

## funapi check

One command to verify an app is healthy — designed as the verification loop a
coding agent can branch on. It boots the app, then runs four checks: routes
load, every model's JSON Schema generates, the OpenAPI spec generates and is
valid JSON, and the spec has not drifted from a committed snapshot.

```bash
$ funapi check
✓ routes       3 route(s) loaded
✓ schemas      all model JSON schemas generate
✓ openapi      spec generates and is valid JSON
✓ spec-drift   no snapshot (run 'funapi check --update-snapshot' to create openapi.snapshot.json)

All checks passed.
```

Exit codes are machine-friendly: **0** when all checks pass, **1** on any
failure. `--json` emits a structured result:

```json
{
  "status": "ok",
  "checks": [
    {"name": "routes", "ok": true, "detail": "3 route(s) loaded"},
    {"name": "openapi", "ok": true, "detail": "spec generates and is valid JSON"}
  ]
}
```

### Spec-drift detection

Commit a snapshot of your OpenAPI spec and `funapi check` fails whenever the
generated spec diverges from it — catching accidental API changes in review or
CI:

```bash
funapi check --update-snapshot   # writes openapi.snapshot.json
```

A missing snapshot is a note, not a failure. When present, any difference
between the generated spec and the snapshot fails the `spec-drift` check with
exit 1; re-run with `--update-snapshot` once the change is intentional.
