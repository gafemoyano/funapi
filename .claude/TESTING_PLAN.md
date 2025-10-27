# Testing Plan for FunApi

## ✅ COMPLETED (2024-10-26)

All planned tests have been implemented and are passing!

**Final Results**: 90 tests, 217 assertions, 0 failures, ~220ms execution

See `TESTING_STATUS.md` for detailed metrics.

---

## Original Plan (For Reference)

## Current State Analysis

### What We Have
- ✅ Basic test setup with Minitest
- ✅ Rack::MockRequest for testing without server
- ✅ Working examples in `examples/` directory (middleware_demo.rb)
- ✅ Demo scripts in `test/` directory (demo_openapi.rb, demo_middleware.rb)
- ❌ **Tests are outdated** - use old `contract:` API instead of `query:` and `body:` schemas
- ❌ **No tests for middleware**
- ❌ **No tests for OpenAPI generation**
- ❌ **No tests for validation errors**
- ❌ **No tests for response schemas**
- ❌ **No tests for async operations**

### Key Insight: Examples as Living Documentation
Our examples are actually **executable integration tests** - they demonstrate real-world usage and can be run to verify the system works. This is valuable! We should:
1. Keep examples as end-to-end demonstrations
2. Add unit tests for component-level testing
3. Document the dual role of examples

## Testing Strategy

### 1. Unit Tests (Component-Level)
**Location**: `test/unit/`

Test individual components in isolation:
- Router (path matching, parameter extraction)
- Schema validation (dry-schema wrapper)
- Middleware chain building
- OpenAPI spec generation
- Response schema filtering

### 2. Integration Tests (API-Level)
**Location**: `test/integration/`

Test full request/response cycle with Rack::MockRequest:
- Route handlers
- Validation errors
- Exception handling
- Middleware integration
- Async operations

### 3. Examples (End-to-End Demonstrations)
**Location**: `examples/`

Keep as living documentation:
- Real server startup
- Complete feature demonstrations
- Can be run manually for smoke testing
- Used in documentation/README

## Implementation Plan

### Phase 1: Fix Existing Tests ⭐⭐⭐⭐⭐
**Priority**: CRITICAL
**Files**: `test/test_fun_api.rb`

- [ ] Update to use `query:` and `body:` schemas instead of `contract:`
- [ ] Add proper async context handling (tests currently fail without Async)
- [ ] Ensure all basic HTTP methods work (GET, POST, PUT, PATCH, DELETE)
- [ ] Verify JSON body parsing
- [ ] Verify query parameter handling
- [ ] Verify path parameter extraction

### Phase 2: Unit Tests for Core Components ⭐⭐⭐⭐⭐
**Priority**: HIGH

#### Router Tests (`test/unit/test_router.rb`)
- [ ] Test path matching (exact, with params, root route)
- [ ] Test parameter extraction
- [ ] Test 404 handling
- [ ] Test route priority/ordering
- [ ] Test special characters in paths

#### Schema Tests (`test/unit/test_schema.rb`)
- [ ] Test schema definition
- [ ] Test validation success
- [ ] Test validation failure
- [ ] Test error message format (FastAPI-style)
- [ ] Test array schemas
- [ ] Test nested schemas
- [ ] Test optional vs required fields

#### Middleware Tests (`test/unit/test_middleware.rb`)
- [ ] Test middleware chain building
- [ ] Test execution order (FIFO)
- [ ] Test middleware with options
- [ ] Test keyword argument handling
- [ ] Test with multiple middleware

### Phase 3: Integration Tests ⭐⭐⭐⭐
**Priority**: HIGH

#### Validation Tests (`test/integration/test_validation.rb`)
- [ ] Test query schema validation
- [ ] Test body schema validation
- [ ] Test validation error responses (422 with detail array)
- [ ] Test array body validation
- [ ] Test missing required fields
- [ ] Test invalid types

#### Response Schema Tests (`test/integration/test_response_schema.rb`)
- [ ] Test response filtering (removes unlisted fields)
- [ ] Test response validation
- [ ] Test array response schemas
- [ ] Test response with nested objects

#### Middleware Integration Tests (`test/integration/test_middleware_integration.rb`)
- [ ] Test CORS middleware (headers added)
- [ ] Test TrustedHost middleware (blocks invalid hosts)
- [ ] Test RequestLogger middleware (logs to buffer)
- [ ] Test middleware + validation interaction
- [ ] Test custom Rack middleware

#### OpenAPI Tests (`test/integration/test_openapi.rb`)
- [ ] Test spec generation
- [ ] Test schema conversion (dry-schema → JSON Schema)
- [ ] Test path parameter extraction
- [ ] Test query parameter generation
- [ ] Test request body schemas
- [ ] Test response schemas
- [ ] Test /openapi.json endpoint
- [ ] Test /docs endpoint (HTML response)

#### Async Tests (`test/integration/test_async.rb`)
- [ ] Test concurrent task execution
- [ ] Test task.wait
- [ ] Test async with middleware
- [ ] Test async error handling

### Phase 4: Exception Handling Tests ⭐⭐⭐
**Priority**: MEDIUM

#### Exception Tests (`test/integration/test_exceptions.rb`)
- [ ] Test HTTPException (404, 400, 500, etc.)
- [ ] Test custom status codes
- [ ] Test custom error messages
- [ ] Test error response format

### Phase 5: Edge Cases & Regression Tests ⭐⭐⭐
**Priority**: MEDIUM

- [ ] Test root route `/` (known bug fixed)
- [ ] Test routes with special characters
- [ ] Test large request bodies
- [ ] Test concurrent requests
- [ ] Test empty responses
- [ ] Test malformed JSON

## Test Organization Structure

Following Sidekiq's approach - **flat structure**, tests organized by functionality:

```
test/
├── test_helper.rb              # Shared test setup
├── test_fun_api.rb             # Basic smoke tests
├── test_router.rb              # Router: path matching, params
├── test_schema.rb              # Schema validation
├── test_middleware.rb          # Middleware chain & built-ins
├── test_validation.rb          # Request validation
├── test_response_schema.rb     # Response filtering
├── test_openapi.rb             # OpenAPI spec generation
├── test_async.rb               # Async operations
├── test_exceptions.rb          # Exception handling
├── demo_middleware.rb          # Manual demo (not automated)
└── demo_openapi.rb             # Manual demo (not automated)
```

Each test file tests functionality whether that requires unit or integration testing.

## Testing Utilities

### Create Test Helpers

**File**: `test/test_helper.rb` (enhance existing)

```ruby
# Helper for creating test apps
def build_test_app(&block)
  FunApi::App.new(title: "Test", version: "1.0.0", &block)
end

# Helper for making async requests (wrap in Async context)
def async_request(app, method, path, **options)
  Async do
    mock_request = Rack::MockRequest.new(app)
    mock_request.send(method, path, **options)
  end.wait
end

# Helper for parsing JSON responses
def parse_json(response)
  JSON.parse(response.body, symbolize_names: true)
end

# Helper for creating test schemas
def test_schema(&block)
  FunApi::Schema.define(&block)
end
```

## Running Tests

### All Tests
```bash
bundle exec rake test
```

### Specific Test File
```bash
bundle exec ruby test/unit/test_router.rb
```

### Specific Test Method
```bash
bundle exec ruby test/unit/test_router.rb -n test_root_route
```

### With Coverage (future)
```bash
bundle exec rake test:coverage
```

## Documentation Updates Needed

### AGENTS.md
Add testing section:
- How to run tests
- How to write new tests
- Testing patterns and helpers
- Mock request examples

### README.md
Add testing section for contributors:
- Running tests
- Test structure
- Coverage expectations

## Success Metrics

- [ ] All existing tests pass
- [ ] >80% code coverage for core components
- [ ] <100ms average test run time (unit tests)
- [ ] <1s average test run time (integration tests)
- [ ] All new features have tests before merging
- [ ] CI runs tests on all PRs

## Implementation Timeline

**Week 1**: Phase 1 (Fix existing tests) + Phase 2 (Router, Schema tests)
**Week 2**: Phase 3 (Validation, Response Schema, Middleware integration)
**Week 3**: Phase 3 cont. (OpenAPI, Async) + Phase 4 (Exceptions)
**Week 4**: Phase 5 (Edge cases) + Documentation updates

## Benefits of This Approach

1. **Confidence**: Catch regressions before they ship
2. **Documentation**: Tests show how to use the API
3. **Refactoring Safety**: Can improve code without breaking functionality
4. **Faster Development**: Quick feedback loop
5. **Examples Stay Simple**: Don't bloat examples with test assertions

## Next Steps

1. Create this plan document ✅
2. Fix existing tests (Phase 1)
3. Set up test structure (create directories)
4. Implement unit tests (Phase 2)
5. Implement integration tests (Phase 3)
6. Add CI/CD test automation
