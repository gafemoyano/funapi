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

## Future Decisions Pending

These are under consideration:

1. **Dependency Injection**: How to implement FastAPI's `Depends()` pattern?
2. **Background Tasks**: Post-response task execution strategy
3. **Path Parameter Types**: Should we validate/coerce path params?
4. **WebSocket Support**: Integration with async architecture
5. **Content Negotiation**: JSON by default, how to add XML/MessagePack?

---

## Non-Decisions (Explicitly Rejected)

### Rails Integration
**Decision**: FunApi remains independent of Rails.
**Reason**: Keep it minimal, different use case.

### Magic DSLs
**Decision**: No heavy DSLs or metaprogramming.
**Reason**: Explicit is better than implicit.

### Database Integration
**Decision**: No built-in ORM or database layer.
**Reason**: Users choose their own (Sequel, ROM, ActiveRecord).

---

## Change Log

- 2024-10-26: Added testing strategy, middleware decisions, documentation strategy
- 2024-09: Initial decisions for core framework
