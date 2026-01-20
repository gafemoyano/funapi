# Testing the Introspection API

This guide shows you multiple ways to test and explore the Runtime Introspection API.

## Quick Test

Run the automated quick test suite:

```bash
ruby examples/introspection_quick_test.rb
```

This runs 12 automated tests covering:
- Basic stats
- Route querying
- Dependency analysis
- Schema inspection
- Health validation
- Search functionality
- Middleware inspection
- JSON export
- Fingerprinting
- Relationships

**Expected output**: All 12 tests should pass with ✅

## Full Demo

Run the comprehensive demo:

```bash
ruby examples/introspection_demo.rb
```

This shows:
- Complete stats overview
- All routes with metadata
- Dependency usage analysis
- Schema field details
- Middleware chain
- Query examples
- Health check
- Relationships graph
- Advanced queries

## AI Use Cases

See practical AI examples:

```bash
ruby examples/introspection_ai_examples.rb
```

Demonstrates 10 AI use cases:
1. API discovery
2. Security pattern detection
3. Consistency validation
4. Code generation from patterns
5. Dead code identification
6. Impact analysis
7. Test generation
8. Documentation generation
9. Refactoring suggestions
10. Codebase explanation

## Interactive Console

Launch an interactive Ruby console with introspection loaded:

```bash
ruby examples/introspection_interactive.rb
```

Then try these commands:

```ruby
# Basic exploration
app.introspect.routes.count
app.introspect.routes.map(&:path)
app.introspect.dependencies.names

# Querying
app.introspect.routes.where_verb('GET')
app.introspect.routes.where_uses_dependency(:db)
app.introspect.routes.search('user')

# Details
route = app.introspect.route('POST', '/users')
route.dependencies
route.body_schema
route.to_h

dep = app.introspect.dependency(:db)
dep.used_by_count
dep.used_by.map(&:path)

schema = app.introspect.schemas.first
schema.fields
schema.required_fields
schema.field_types

# Analysis
app.introspect.stats
app.introspect.validate
app.introspect.relationships
app.introspect.to_json
```

Press Ctrl+D to exit.

## Unit Tests

Run the test suite:

```bash
# Run just introspection tests
bundle exec ruby -Itest test/test_introspection.rb

# Run all tests
bundle exec rake test
```

**Expected**: 34 introspection tests, all passing

## Manual Testing

Create your own test:

```ruby
require_relative 'lib/fun_api'

# Create an app
app = FunApi::App.new do |api|
  api.register(:db) { {} }
  
  api.get '/test', depends: [:db] do |_input, _req, _task, db:|
    [{}, 200]
  end
end

# Test introspection
puts app.introspect.routes.count              # => 1
puts app.introspect.routes.first.path         # => "/test"
puts app.introspect.routes.first.dependencies # => [:db]
puts app.introspect.stats                     # => {...}
```

## Testing Specific Features

### Test Route Queries

```ruby
app.introspect.routes.where_verb('GET')
app.introspect.routes.where_uses_dependency(:db)
app.introspect.routes.where_has_body_schema
app.introspect.routes.where_path_param('id')
app.introspect.routes.search('user')
```

### Test Dependency Analysis

```ruby
app.introspect.dependencies.unused
app.introspect.dependencies.most_used(5)
app.introspect.dependencies.with_cleanup
app.introspect.dependency(:db).used_by_count
```

### Test Schema Introspection

```ruby
app.introspect.schemas.where_has_field(:email)
app.introspect.schemas.where_required_field(:id)
app.introspect.schemas.field_usage
```

### Test Health Validation

```ruby
health = app.introspect.validate
puts health[:score]    # 0.0 to 1.0
puts health[:issues]   # Array of issues
puts health[:warnings] # Array of warnings
```

### Test Change Detection

```ruby
fp1 = app.introspect.fingerprint
app.get '/new' do |_input, _req, _task|
  [{}, 200]
end
app.introspect.clear_cache
fp2 = app.introspect.fingerprint
puts fp1 != fp2  # => true
```

## Common Test Patterns

### Finding Routes Without Schemas

```ruby
routes_without_schemas = app.introspect.routes.where { |r|
  !r.has_body_schema? && !r.has_query_schema? && !r.has_response_schema?
}
```

### Finding Unused Dependencies

```ruby
unused = app.introspect.dependencies.unused
unused.each { |dep| puts "Unused: #{dep.name}" }
```

### Analyzing Dependency Impact

```ruby
dep = app.introspect.dependency(:db)
puts "#{dep.name} is used by:"
dep.used_by.each { |route| puts "  - #{route.verb} #{route.path}" }
```

### Generating Route Templates

```ruby
template = app.introspect.route('GET', '/users/:id')
similar = template.similar_routes
similar.each { |r| puts "Similar: #{r.path}" }
```

## Troubleshooting

### Introspection returns empty results

Make sure you're calling `introspect` on your app instance:
```ruby
app = FunApi::App.new do |api|
  # ... define routes ...
end

# Wrong:
FunApi.introspect.routes

# Correct:
app.introspect.routes
```

### Schema names show as "AnonymousSchema"

Assign schemas to constants:
```ruby
# Wrong (anonymous):
app.post '/users', body: FunApi::Schema.define { ... }

# Correct (named):
UserSchema = FunApi::Schema.define { ... }
app.post '/users', body: UserSchema
```

### Cache not updating after changes

Clear the cache:
```ruby
app.get '/new_route' { [{}, 200] }
app.introspect.clear_cache  # Important!
app.introspect.routes.count # Now shows new route
```

### ObjectSpace warnings

These are harmless warnings from schema name discovery. They don't affect functionality and only appear in development.

## Performance Testing

```ruby
require 'benchmark'

app = create_large_app_with_100_routes

Benchmark.bm do |x|
  x.report("first call:")     { app.introspect.routes }
  x.report("cached call:")    { app.introspect.routes }
  x.report("stats:")          { app.introspect.stats }
  x.report("validate:")       { app.introspect.validate }
  x.report("to_json:")        { app.introspect.to_json }
end
```

## Integration Testing

Test introspection with your actual application:

```ruby
# In your app
app = FunApi::App.new do |api|
  # ... your actual routes ...
end

# Validate structure
health = app.introspect.validate
raise "App health too low" if health[:score] < 0.8

# Ensure all POST routes have schemas
posts = app.introspect.routes.where_verb('POST')
missing = posts.where { |r| !r.has_body_schema? }
raise "POST routes missing schemas" if missing.any?

# Verify no unused dependencies
unused = app.introspect.dependencies.unused
warn "Unused dependencies: #{unused.map(&:name)}" if unused.any?
```

## Next Steps

- Explore the full API in `.claude/INTROSPECTION_IMPLEMENTATION.md`
- Read source code examples in `examples/`
- Check test suite in `test/test_introspection.rb`
- Try building your own introspection-based tools!
