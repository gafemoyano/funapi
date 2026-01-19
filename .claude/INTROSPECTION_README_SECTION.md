# Runtime Introspection API (README Section)

Add this section to README.md to document the introspection feature:

---

## Runtime Introspection

FunApi provides a comprehensive introspection API that allows you (and AI agents) to programmatically understand and query your application structure at runtime.

### Basic Usage

```ruby
app = FunApi::App.new do |api|
  api.register(:db) { Database.connect }
  
  api.get '/users', depends: [:db] do |_input, _req, _task, db:|
    [db.all_users, 200]
  end
end

# Introspect your application
app.introspect.routes.count           # => 1
app.introspect.dependencies.names     # => [:db]
app.introspect.stats                  # => {...}
```

### Exploring Routes

```ruby
# Get all routes
app.introspect.routes

# Query routes
app.introspect.routes.where_verb('GET')
app.introspect.routes.where_uses_dependency(:db)
app.introspect.routes.where_has_body_schema
app.introspect.routes.search('user')

# Get route details
route = app.introspect.route('POST', '/users')
route.verb                  # => "POST"
route.path                  # => "/users"
route.dependencies          # => [:db, :logger]
route.body_schema           # => UserCreateSchema
route.response_schema       # => UserOutputSchema
route.path_params           # => []
route.has_body_schema?      # => true
```

### Analyzing Dependencies

```ruby
# Get all dependencies
app.introspect.dependencies

# Find unused dependencies
app.introspect.dependencies.unused

# Find most used dependencies
app.introspect.dependencies.most_used(5)

# Analyze specific dependency
dep = app.introspect.dependency(:db)
dep.used_by_count          # => 12
dep.used_by.map(&:path)    # => ["/users", "/posts", ...]
dep.type                   # => :simple | :managed | :block
```

### Inspecting Schemas

```ruby
# Get all schemas
app.introspect.schemas

# Query schemas
app.introspect.schemas.where_has_field(:email)
app.introspect.schemas.where_required_field(:id)

# Get schema details
schema = app.introspect.schema(UserCreateSchema)
schema.name                # => "UserCreateSchema"
schema.fields              # => [:name, :email, :age]
schema.required_fields     # => [:name, :email]
schema.optional_fields     # => [:age]
schema.field_types         # => {name: :string, email: :string, ...}
schema.used_by_routes      # => [RouteInfo, ...]
```

### Application Health

```ruby
# Get application statistics
stats = app.introspect.stats
stats[:routes]              # => 15
stats[:dependencies]        # => 5
stats[:schemas]             # => 8
stats[:most_common_dependency]  # => :db
stats[:schema_coverage]     # => 0.85

# Validate application health
health = app.introspect.validate
health[:score]              # => 0.95 (0.0 to 1.0)
health[:issues]             # => [{type: :unused_dependency, name: :cache}]
health[:warnings]           # => [{type: :missing_response_schema, path: "/"}]
```

### Dependency Relationships

```ruby
# Get dependency usage map
rels = app.introspect.relationships
# => {
#   db: { routes: 12, route_paths: ["/users", "/posts", ...] },
#   logger: { routes: 5, route_paths: [...] }
# }

# Check for changes
fingerprint = app.introspect.fingerprint
# ... make changes ...
app.introspect.changed_since?(fingerprint)  # => true
```

### Export to JSON

```ruby
# Export complete application structure
json = app.introspect.to_json
# Use for documentation, analysis, or AI consumption
```

### AI-Friendly Features

The introspection API enables powerful AI-driven workflows:

**Discovery**:
```ruby
# AI: "What routes exist?"
app.introspect.routes.map(&:path)
```

**Code Generation**:
```ruby
# AI: "Create a similar route"
template = app.introspect.route('GET', '/users/:id')
# Use template.dependencies, template.path_params, etc.
```

**Validation**:
```ruby
# AI: "Find inconsistencies"
app.introspect.routes
  .where_verb('POST')
  .where { |r| !r.has_body_schema? }
```

**Testing**:
```ruby
# AI: "Generate tests for this route"
route = app.introspect.route('POST', '/users')
schema = app.introspect.schema(route.body_schema)
test_data = schema.example_data  # => {name: "John Doe", email: "user@example.com"}
```

### Examples

See comprehensive examples:
- `examples/introspection_demo.rb` - Full feature demo
- `examples/introspection_quick_test.rb` - Quick automated tests
- `examples/introspection_ai_examples.rb` - AI use cases
- `examples/introspection_interactive.rb` - Interactive console

Run any example:
```bash
ruby examples/introspection_demo.rb
```

### Testing Guide

See `TESTING_INTROSPECTION.md` for detailed testing instructions and patterns.

---
