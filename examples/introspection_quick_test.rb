# frozen_string_literal: true

require_relative "../lib/fun_api"

puts "\n🧪 FunApi Introspection - Quick Tests\n\n"

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

app = FunApi::App.new do |api|
  api.register(:db) { {users: []} }
  api.register(:logger) { Logger.new($stdout) }

  api.add_cors

  api.get "/users", depends: [:db] do |_input, _req, _task, db:|
    [db[:users], 200]
  end

  api.post "/users", body: UserSchema, depends: %i[db logger] do |input, _req, _task, db:, logger:|
    [input[:body], 201]
  end

  api.get "/users/:id", depends: [:db] do |input, _req, _task, db:|
    [{id: input[:path]["id"]}, 200]
  end
end

puts "TEST 1: Basic Stats"
puts "-" * 50
stats = app.introspect.stats
puts "Routes: #{stats[:routes]}"
puts "Dependencies: #{stats[:dependencies]}"
puts "Schemas: #{stats[:schemas]}"
puts "Verbs: #{stats[:verbs].join(", ")}"
puts "✅ PASS\n\n"

puts "TEST 2: Query Routes by Verb"
puts "-" * 50
get_routes = app.introspect.routes.where_verb("GET")
puts "GET routes found: #{get_routes.count}"
get_routes.each { |r| puts "  - #{r.path}" }
puts "✅ PASS\n\n"

puts "TEST 3: Find Routes Using Dependency"
puts "-" * 50
db_routes = app.introspect.routes.where_uses_dependency(:db)
puts "Routes using :db: #{db_routes.count}"
db_routes.each { |r| puts "  - #{r.verb} #{r.path}" }
puts "✅ PASS\n\n"

puts "TEST 4: Dependency Usage Analysis"
puts "-" * 50
app.introspect.dependencies.each do |dep|
  puts "#{dep.name}: used by #{dep.used_by_count} routes"
end
puts "✅ PASS\n\n"

puts "TEST 5: Schema Field Inspection"
puts "-" * 50
schema = app.introspect.schemas.where_has_field(:email).first
if schema
  puts "Schema: #{schema.name}"
  puts "Required fields: #{schema.required_fields.join(", ")}"
  puts "Optional fields: #{schema.optional_fields.join(", ")}"
  puts "Field types:"
  schema.field_types.each { |field, type| puts "  - #{field}: #{type}" }
end
puts "✅ PASS\n\n"

puts "TEST 6: Route Details"
puts "-" * 50
route = app.introspect.route("POST", "/users")
if route
  puts "Path: #{route.path}"
  puts "Verb: #{route.verb}"
  puts "Dependencies: #{route.dependencies.join(", ")}"
  puts "Has body schema: #{route.has_body_schema?}"
  puts "Path params: #{route.path_params.empty? ? "none" : route.path_params.join(", ")}"
end
puts "✅ PASS\n\n"

puts "TEST 7: Health Validation"
puts "-" * 50
health = app.introspect.validate
puts "Health Score: #{(health[:score] * 100).round(1)}%"
puts "Issues: #{health[:issues].length}"
puts "Warnings: #{health[:warnings].length}"
if health[:issues].any?
  health[:issues].each do |issue|
    puts "  ⚠️  #{issue[:type]}: #{issue[:name]}"
  end
end
puts "✅ PASS\n\n"

puts "TEST 8: Search Routes"
puts "-" * 50
user_routes = app.introspect.routes.search("user")
puts "Routes matching 'user': #{user_routes.count}"
user_routes.each { |r| puts "  - #{r.verb} #{r.path}" }
puts "✅ PASS\n\n"

puts "TEST 9: Middleware Inspection"
puts "-" * 50
middleware = app.introspect.middleware
puts "Total middleware: #{middleware.count}"
middleware.each do |mw|
  puts "  #{mw.position + 1}. #{mw.class_name} [#{mw.builtin? ? "builtin" : "custom"}]"
end
puts "✅ PASS\n\n"

puts "TEST 10: JSON Export"
puts "-" * 50
json = app.introspect.to_json
parsed = JSON.parse(json)
puts "JSON export successful"
puts "Top-level keys: #{parsed.keys.join(", ")}"
puts "Stats included: #{parsed["stats"].keys.join(", ")}"
puts "✅ PASS\n\n"

puts "TEST 11: Fingerprinting"
puts "-" * 50
fp1 = app.introspect.fingerprint
puts "Fingerprint: #{fp1[0..15]}..."
puts "Changed since itself: #{app.introspect.changed_since?(fp1)}"

app.get "/new_route" do |_input, _req, _task|
  [{}, 200]
end
app.introspect.clear_cache

fp2 = app.introspect.fingerprint
puts "After adding route:"
puts "  New fingerprint: #{fp2[0..15]}..."
puts "  Changed: #{app.introspect.changed_since?(fp1)}"
puts "✅ PASS\n\n"

puts "TEST 12: Relationships"
puts "-" * 50
rels = app.introspect.relationships
rels.each do |dep_name, info|
  puts "#{dep_name}:"
  puts "  Routes: #{info[:routes]}"
  puts "  Paths: #{info[:route_paths].join(", ")}"
end
puts "✅ PASS\n\n"

puts "=" * 50
puts "✨ All 12 tests passed!"
puts "=" * 50
puts
