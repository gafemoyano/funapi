# FunApi - Architectural Decisions

This document records key architectural and design decisions made during the development of FunApi.

## Testing Strategy (2024-10-26)

### Decision: Flat Test Structure

**Context**: Needed to organize tests for the framework. Options were nested directories (unit/, integration/) vs flat structure.

**Decision**: Use flat test structure following Sidekiq's pattern.

**Rationale**:
- Simplicity - easier to find tests
- Flexibility - tests can be unit or integration as needed
- No artificial boundaries - test what matters, not how
- Proven pattern - Sidekiq has excellent test organization
- Library-friendly - FunApi is a library, not an application

**Implementation**:
```
test/
├── test_helper.rb
├── test_fun_api.rb       # Basic smoke tests
├── test_router.rb        # Router functionality
├── test_schema.rb        # Validation
├── test_middleware.rb    # Middleware chain
├── test_validation.rb    # Request validation
├── test_response_schema.rb
├── test_async.rb
└── test_exceptions.rb
```

**Result**: 90 tests, 217 assertions, all passing in ~220ms

---

## Middleware System (2024-10-26)

### Decision: Rack-Compatible Middleware with FastAPI-Style Convenience

**Context**: Needed middleware support. Options: Build custom system vs leverage Rack ecosystem.

**Decision**: Support standard Rack middleware PLUS provide FastAPI-style convenience methods.

**Rationale**:
- Leverage battle-tested Rack ecosystem (15+ years, 100+ middleware)
- No reinvention - delegate to proven libraries (rack-cors, Rack::Deflater)
- FastAPI-like DX - convenience methods for common use cases
- Zero lock-in - users can use any Rack middleware
- Async compatible - Rack 3.0+ supports async natively

**Implementation**:
```ruby
# Standard Rack middleware
app.use Rack::Attack
app.use Rack::Session::Cookie, secret: 'key'

# FunApi convenience methods
app.add_cors(allow_origins: ['*'])
app.add_trusted_host(allowed_hosts: ['example.com'])
app.add_request_logger
```

**Built-in Middleware**:
- CORS (wraps rack-cors)
- TrustedHost (custom implementation)
- RequestLogger (custom with async awareness)
- Gzip (delegates to Rack::Deflater)

**Result**: Full Rack compatibility + excellent developer experience

---

## Middleware Execution Order (2024-10-26)

### Decision: Standard Rack Ordering (LIFO wrapping, FIFO execution)

**Context**: How should middleware execute when multiple are registered?

**Decision**: First registered middleware runs first (outermost layer).

**Rationale**:
- Standard Ruby/Rack convention
- Expected by Rack developers
- Well-documented behavior
- Works with all existing Rack middleware

**Example**:
```ruby
app.use Middleware1  # Executes FIRST
app.use Middleware2  # Executes SECOND
# Router executes LAST
```

Request flow: MW1 → MW2 → Router → MW2 → MW1

---

## OpenAPI Implementation (2024-09)

### Decision: Automatic Schema Extraction

**Context**: How to generate OpenAPI specs from dry-schema definitions?

**Decision**: Introspect dry-schema at runtime and convert to JSON Schema.

**Rationale**:
- No manual duplication
- Single source of truth (the schema)
- Automatic documentation updates
- FastAPI-like experience

**Implementation**:
- SchemaConverter: dry-schema → JSON Schema
- SpecGenerator: routes + schemas → OpenAPI 3.0.3 spec
- Auto-register /openapi.json and /docs endpoints

---

## Response Schema Filtering (2024-09)

### Decision: Security-First Response Filtering

**Context**: How to handle sensitive data in responses (passwords, tokens)?

**Decision**: Response schemas filter output to only include specified fields.

**Rationale**:
- Security by default
- Prevent accidental data leaks
- FastAPI's response_model pattern
- Explicit is better than implicit

**Example**:
```ruby
UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  # password NOT included
end

api.get '/user', response_schema: UserOutputSchema do
  user = { id: 1, name: 'Alice', password: 'secret' }
  [user, 200]  # Password automatically filtered
end
```

---

## Async-First Design (2024-09)

> **⚠️ Superseded (2026-07):** the `task` parameter will be removed from the handler signature in Phase 4 (issue #8) in favor of structured-concurrency helpers. Old signature keeps working during a deprecation window.

### Decision: Async::Task as Third Handler Parameter

**Context**: How to expose async capabilities to route handlers?

**Decision**: Pass `Async::Task` as third parameter to all handlers.

**Rationale**:
- Explicit async access
- No magic globals
- True concurrent execution
- Ruby's Async library is mature

**Example**:
```ruby
api.get '/dashboard' do |input, req, task|
  user_task = task.async { fetch_user }
  posts_task = task.async { fetch_posts }
  
  [{ user: user_task.wait, posts: posts_task.wait }, 200]
end
```

**Trade-off**: Three parameters instead of two, but explicitness wins.

---

## Router Root Route Fix (2024-10-26)

### Decision: Special-Case Root Route `/`

**Context**: Regex generation failed for `/` route (empty regex).

**Decision**: Explicitly handle `/` as special case before regex generation.

**Rationale**:
- `/` is common and important
- Regex `/\A\z/` doesn't match `/`
- Simple fix with no overhead
- Prevents future bugs

**Implementation**:
```ruby
if path == '/'
  regex = '/'
else
  # normal regex generation
end
```

---

## Validation Error Format (2024-09)

### Decision: FastAPI-Compatible Error Format

**Context**: How to structure validation errors?

**Decision**: Use FastAPI's error format with `detail` array.

**Rationale**:
- Familiar to FastAPI users
- Structured and parseable
- Clear error location information
- Industry standard

**Format**:
```json
{
  "detail": [
    {
      "loc": ["body", "email"],
      "msg": "is missing",
      "type": "value_error"
    }
  ]
}
```

---

## Schema Validation (2024-09)

### Decision: dry-schema Over ActiveModel

**Context**: Which validation library to use?

**Decision**: Use dry-schema for validation.

**Rationale**:
- Lightweight (no Rails dependency)
- Functional approach (no mutations)
- Better API error messages
- Type coercion built-in
- Fast and battle-tested

**Trade-off**: Less familiar to Rails developers, but better fit for APIs.

---

## Server Choice (2024-09)

### Decision: Falcon as Default Server

**Context**: Which Rack server to recommend?

**Decision**: Falcon for development and production.

**Rationale**:
- Native async support
- Built for Async library
- Better concurrency for I/O-bound work
- Aligns with async-first philosophy

**Note**: Any Rack 3+ server will work (Puma, Unicorn, etc.)

---

## Documentation Strategy (2024-10-26)

### Decision: Dual Documentation (README + AGENTS.md)

**Context**: How to document for both humans and AI agents?

**Decision**: 
- README.md for human users (features, examples)
- AGENTS.md for AI coding agents (architecture, testing, conventions)

**Rationale**:
- Following agents.md standard
- Different audiences need different info
- Keeps README concise
- Provides deep context for agents

---

## Examples as Documentation (2024-10-26)

### Decision: Executable Examples > Test Assertions

**Context**: Should examples be automated tests?

**Decision**: Keep examples simple and executable, separate from test suite.

**Rationale**:
- Examples show real usage
- Can be run manually for smoke testing
- Don't clutter with assertions
- Living documentation
- Test suite covers thorough testing

**Organization**:
- `examples/` - Runnable demos
- `test/` - Automated tests
- `test/demo_*.rb` - Reference demos (not automated)

---

## Dependency Injection (2024-10-27)

### Decision: Block-Based Dependencies with Cleanup

**Context**: Need DI with automatic resource cleanup. Evaluated: dry-system, tuples, context managers, blocks.

**Decision**: Ruby blocks with `ensure` for lifecycle management.

**Rationale**:
- Most idiomatic Ruby (matches `File.open`, `Mutex.synchronize`)
- `ensure` guarantees cleanup, even on errors
- FastAPI parity (context managers)
- Lightweight (uses Fiber, no heavy deps)

**Pattern**:
```ruby
api.register(:db) do |provide|
  conn = Database.connect
  provide.call(conn)
ensure
  conn.close
end

api.get '/users', depends: [:db] do |input, req, task, db:|
  [db.all_users, 200]
end
```

**Features**:
- Request-scoped caching
- Nested dependencies with `FunApi::Depends()`
- Three patterns: simple, tuple (compat), block (preferred)
- Cleanup in `ensure` after response sent

**Result**: 121 tests passing, FastAPI-aligned.

---

## Dependency Injection: Not dry-system (2024-10-27)

### Decision: Custom Lightweight DI

**Context**: dry-system exists but designed for different use case.

**Decision**: Build custom DI using only dry-container.

**Rationale**:
- dry-system = constructor injection, we need parameter injection
- FunApi is minimal, dry-system is comprehensive
- Custom solution maps 1:1 to FastAPI's `Depends()`

**Used**: dry-container (registry only)
**Skipped**: dry-system, dry-auto_inject, dry-effects

---

## Vision & Positioning (2026-07)

### Decision: "The Ruby framework for streaming, AI-era APIs"

**Context**: Sharpening the pitch beyond "Ruby's FastAPI". Rails won't be async for years; the socketry stack is mature; AI-era APIs are streaming-shaped.

**Decision**: Position FunApi around async/streaming as the differentiator, with explicit schemas-as-values as both the DX and the agent-experience (AX) story. Roadmap tracked on GitHub (master plan: issue #4, phases #5–#10).

---

## FunApi::Model as Owned Facade (2026-07)

### Decision: Own the public schema/model API; dry-schema is an engine, not the interface

**Context**: dry-schema gives validation only — no serialization/filtering from objects, and exposing its DSL directly ties FunApi's public API to DryRB's ideology (the "Hanami trap").

**Decision**: Build `FunApi::Model` — one declaration gives validation + coercion + serialization + JSON Schema. Wrap dry-schema internally at first; keep the option to replace the engine without breaking users. (Issue #7.)

---

## Sequel as the Blessed Data Layer (2026-07)

### Decision: Sequel + fibered connection pool, not socketry's `db`

**Context**: Evaluated trajectory, not just current state. Sequel: monthly releases, 300–700K downloads/version, 5K stars. socketry `db`: ~62K total downloads, 61 stars, sporadic commits — flat trajectory. `pg` >= 1.3 is fiber-scheduler-aware, so Sequel+pg is non-blocking under Falcon anyway.

**Decision**: Bless Sequel with the vendored `FiberedConnectionPool` as The Path; drop `db`/`db-postgres` test dependencies. (Issue #8.)

---

## Knowledge Base on GitHub (2026-07)

### Decision: Plans live in GitHub issues; this file records decisions only

**Context**: `.claude/` had accumulated 14 dated plan/status files for completed work.

**Decision**: Historical plan files deleted. Roadmap and active plans are GitHub issues (master: #4). This file remains the ADR log.

---

## Non-Decisions (Explicitly Rejected)

### Rails Integration
**Decision**: FunApi remains independent of Rails.
**Reason**: Keep it minimal, different use case.

### Magic DSLs
**Decision**: No heavy DSLs or metaprogramming.
**Reason**: Explicit is better than implicit.

### Database Integration
> **⚠️ Superseded (2026-07):** see "Sequel as the Blessed Data Layer" below. FunApi still won't ship an ORM, but it now documents and tests one blessed path.

**Decision**: No built-in ORM or database layer.
**Reason**: Users choose their own (Sequel, ROM, ActiveRecord).

---

## Change Log

- 2026-07-18: Vision/positioning, FunApi::Model, Sequel bet, GitHub knowledge base; superseded task-param and no-database decisions
- 2024-10-27: Added dependency injection decisions
- 2024-10-26: Testing, middleware, documentation strategies
- 2024-09: Initial core framework decisions
