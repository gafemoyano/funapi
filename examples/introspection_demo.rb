# frozen_string_literal: true

require_relative "../lib/fun_api"

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

app = FunApi::App.new(
  title: "Introspection Demo API",
  version: "1.0.0",
  description: "Demonstrating runtime introspection capabilities"
) do |api|
  api.register(:db) { {users: []} }
  api.register(:logger) { Logger.new($stdout) }
  api.register(:cache) { {} }

  api.add_cors(allow_origins: ["*"])
  api.add_request_logger

  api.get "/" do |_input, _req, _task|
    [{message: "Welcome to Introspection Demo"}, 200]
  end

  api.get "/users", query: QuerySchema, response_schema: [UserOutputSchema],
    depends: [:db] do |_input, _req, _task, db:|
    [db[:users], 200]
  end

  api.get "/users/:id", response_schema: UserOutputSchema, depends: [:db] do |input, _req, _task, db:|
    user = db[:users].find { |u| u[:id] == input[:path]["id"].to_i }
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    [user, 200]
  end

  api.post "/users", body: UserCreateSchema, response_schema: UserOutputSchema,
    depends: %i[db logger] do |input, _req, _task, db:, logger:|
    user = input[:body].merge(id: db[:users].length + 1)
    db[:users] << user
    logger.info("Created user: #{user[:name]}")
    [user, 201]
  end

  api.delete "/users/:id", depends: %i[db logger] do |input, _req, _task, db:, logger:|
    id = input[:path]["id"].to_i
    user = db[:users].find { |u| u[:id] == id }
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    db[:users].reject! { |u| u[:id] == id }
    logger.info("Deleted user: #{user[:name]}")
    [{message: "User deleted"}, 200]
  end
end

puts "\n" + ("=" * 80)
puts "FunApi Runtime Introspection Demo"
puts "=" * 80

puts "\n📊 STATS"
puts "-" * 80
stats = app.introspect.stats
puts "Total Routes: #{stats[:routes]}"
puts "Total Dependencies: #{stats[:dependencies]}"
puts "Total Schemas: #{stats[:schemas]}"
puts "Total Middleware: #{stats[:middleware]}"
puts "HTTP Verbs Used: #{stats[:verbs].join(", ")}"
puts "Path Parameters: #{stats[:path_params].join(", ")}"
puts "Most Common Dependency: #{stats[:most_common_dependency]}"
puts "Schema Coverage: #{(stats[:schema_coverage] * 100).round(1)}%"

puts "\n🛣️  ROUTES"
puts "-" * 80
app.introspect.routes.each do |route|
  deps_str = route.dependencies.empty? ? "none" : route.dependencies.join(", ")
  schemas = []
  schemas << "body:#{route.to_h[:body_schema]}" if route.has_body_schema?
  schemas << "query:#{route.to_h[:query_schema]}" if route.has_query_schema?
  schemas << "response:#{route.to_h[:response_schema]}" if route.has_response_schema?
  schema_str = schemas.empty? ? "no schemas" : schemas.join(", ")

  puts "#{route.verb.ljust(6)} #{route.path.ljust(20)} | deps: #{deps_str.ljust(15)} | #{schema_str}"
end

puts "\n📦 DEPENDENCIES"
puts "-" * 80
app.introspect.dependencies.each do |dep|
  type_str = dep.type.to_s.ljust(10)
  usage_str = "#{dep.used_by_count} routes"
  cleanup_str = dep.cleanup_defined? ? "✓ cleanup" : "✗ no cleanup"
  puts "#{dep.name.to_s.ljust(15)} | type: #{type_str} | used by: #{usage_str.ljust(10)} | #{cleanup_str}"
end

puts "\n📋 SCHEMAS"
puts "-" * 80
app.introspect.schemas.each do |schema|
  req_fields = schema.required_fields.join(", ")
  opt_fields = schema.optional_fields.join(", ")
  used_as = schema.used_as.join(", ")
  puts "\n#{schema.name}"
  puts "  Required: #{req_fields.empty? ? "none" : req_fields}"
  puts "  Optional: #{opt_fields.empty? ? "none" : opt_fields}"
  puts "  Used as: #{used_as}"
  puts "  Used by: #{schema.used_by_routes.map(&:path).join(", ")}"
end

puts "\n🔧 MIDDLEWARE"
puts "-" * 80
app.introspect.middleware.chain_order.each do |mw|
  builtin_str = mw.builtin? ? "[builtin]" : "[custom]"
  opts_str = mw.options.empty? ? "" : " - options: #{mw.options.inspect}"
  puts "#{mw.position + 1}. #{mw.class_name} #{builtin_str}#{opts_str}"
end

puts "\n🔍 QUERY EXAMPLES"
puts "-" * 80

puts "\nRoutes using :db dependency:"
app.introspect.routes.where_uses_dependency(:db).each do |route|
  puts "  - #{route.verb} #{route.path}"
end

puts "\nPOST routes:"
app.introspect.routes.where_verb("POST").each do |route|
  puts "  - #{route.path} (body: #{route.to_h[:body_schema]})"
end

puts "\nRoutes with path parameter 'id':"
app.introspect.routes.where_path_param("id").each do |route|
  puts "  - #{route.verb} #{route.path}"
end

puts "\nSchemas with 'email' field:"
app.introspect.schemas.where_has_field(:email).each do |schema|
  puts "  - #{schema.name}"
end

puts "\n🏥 HEALTH CHECK"
puts "-" * 80
health = app.introspect.validate
puts "Health Score: #{(health[:score] * 100).round(1)}%"

if health[:issues].any?
  puts "\nIssues:"
  health[:issues].each do |issue|
    puts "  ⚠️  #{issue[:type]}: #{issue[:name] || issue[:path]}"
  end
end

if health[:warnings].any?
  puts "\nWarnings:"
  health[:warnings].each do |warning|
    puts "  ⚡ #{warning[:type]}: #{warning[:path]} (#{warning[:verb]})" if warning[:path]
  end
end

puts "\n📈 RELATIONSHIPS"
puts "-" * 80
app.introspect.relationships.each do |dep_name, info|
  puts "#{dep_name}: used by #{info[:routes]} route(s)"
  info[:route_paths].each do |path|
    puts "  - #{path}"
  end
end

puts "\n🔑 FINGERPRINT"
puts "-" * 80
puts "Current fingerprint: #{app.introspect.fingerprint[0..15]}..."

puts "\n💡 ADVANCED QUERIES"
puts "-" * 80

puts "\nUnused dependencies:"
unused = app.introspect.dependencies.unused
if unused.empty?
  puts "  None - all dependencies are used!"
else
  unused.each { |d| puts "  - #{d.name}" }
end

puts "\nMost used dependencies:"
app.introspect.dependencies.most_used(3).each do |dep|
  puts "  - #{dep.name}: #{dep.used_by_count} routes"
end

puts "\nField usage across schemas:"
field_usage = app.introspect.schemas.field_usage
field_usage.sort_by { |_f, count| -count }.first(5).each do |field, count|
  puts "  - #{field}: appears in #{count} schema(s)"
end

puts "\n" + ("=" * 80)
puts "✨ Introspection API ready to help AI understand your application!"
puts "=" * 80
puts "\n"
