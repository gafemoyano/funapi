# frozen_string_literal: true

require_relative "../lib/fun_api"

puts "\n" + ("=" * 80)
puts "FunApi Introspection - AI Use Case Examples"
puts "=" * 80
puts "\nDemonstrating how AI agents can use introspection to understand and work"
puts "with FunApi applications.\n\n"

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:password).filled(:string)
end

app = FunApi::App.new do |api|
  api.register(:db) { {users: [], posts: []} }
  api.register(:auth) { {tokens: {}} }
  api.register(:logger) { Logger.new($stdout) }
  api.register(:cache) { {} }

  api.add_cors
  api.add_request_logger

  api.get "/" do |_input, _req, _task|
    [{message: "API Home"}, 200]
  end

  api.get "/users", depends: [:db] do |_input, _req, _task, db:|
    [db[:users], 200]
  end

  api.post "/users", body: UserSchema, depends: %i[db logger] do |input, _req, _task, db:, logger:|
    [input[:body], 201]
  end

  api.get "/users/:id", depends: [:db] do |input, _req, _task, db:|
    [{id: input[:path]["id"]}, 200]
  end

  api.get "/posts", depends: %i[db cache] do |_input, _req, _task, db:, cache:|
    [db[:posts], 200]
  end
end

puts "🤖 AI USE CASE 1: Understanding the API"
puts "-" * 80
puts "AI: 'What routes are available in this application?'"
puts
routes = app.introspect.routes
puts "Found #{routes.count} routes:"
routes.each do |route|
  puts "  #{route.verb.ljust(6)} #{route.path}"
end
puts "\n✅ AI can discover all endpoints\n\n"

puts "🤖 AI USE CASE 2: Finding Authentication Patterns"
puts "-" * 80
puts "AI: 'Which routes require authentication?'"
puts
auth_routes = app.introspect.routes.where do |r|
  r.dependencies.any? { |d| d.to_s.include?("auth") }
end
puts "Routes with authentication:"
if auth_routes.empty?
  puts "  None found - this might be a security issue!"
else
  auth_routes.each { |r| puts "  - #{r.verb} #{r.path}" }
end
puts "\n✅ AI can identify security patterns\n\n"

puts "🤖 AI USE CASE 3: Detecting Inconsistencies"
puts "-" * 80
puts "AI: 'Are there any routes that don't follow best practices?'"
puts
issues = []

post_without_schema = app.introspect.routes
  .where_verb("POST")
  .where { |r| !r.has_body_schema? }
issues << "POST routes without body schema: #{post_without_schema.map(&:path).join(", ")}" if post_without_schema.any?

routes_with_id = app.introspect.routes.where_path_param("id")
routes_without_db = routes_with_id.where { |r| !r.uses_dependency?(:db) }
issues << "Routes with :id but no :db dependency: #{routes_without_db.map(&:path).join(", ")}" if routes_without_db.any?

get_without_cache = app.introspect.routes
  .where_verb("GET")
  .where { |r| !r.uses_dependency?(:cache) && !r.path.include?(":id") }
issues << "List endpoints without caching: #{get_without_cache.map(&:path).join(", ")}" if get_without_cache.count > 2

if issues.any?
  puts "Found potential issues:"
  issues.each { |issue| puts "  ⚠️  #{issue}" }
else
  puts "  ✅ No issues found!"
end
puts "\n✅ AI can validate code quality\n\n"

puts "🤖 AI USE CASE 4: Generating Similar Routes"
puts "-" * 80
puts "AI: 'I want to create a /posts/:id route similar to /users/:id'"
puts
template = app.introspect.route("GET", "/users/:id")
if template
  puts "Using /users/:id as template:"
  puts "  Path params: #{template.path_params.join(", ")}"
  puts "  Dependencies: #{template.dependencies.join(", ")}"
  puts "  Has response schema: #{template.has_response_schema?}"
  puts
  puts "Generated code:"
  puts <<~RUBY
    api.get '/posts/:id', depends: #{template.dependencies.inspect} do |input, _req, _task, #{template.dependencies.map { |d| "#{d}:" }.join(", ")}|
      id = input[:path]['id'].to_i
      post = #{template.dependencies.first}[:posts].find { |p| p[:id] == id }
      raise FunApi::HTTPException.new(status_code: 404, detail: 'Post not found') unless post
      [post, 200]
    end
  RUBY
end
puts "✅ AI can generate code from patterns\n\n"

puts "🤖 AI USE CASE 5: Finding Unused Code"
puts "-" * 80
puts "AI: 'What dependencies are registered but never used?'"
puts
unused_deps = app.introspect.dependencies.unused
if unused_deps.any?
  puts "Unused dependencies (can be removed):"
  unused_deps.each do |dep|
    puts "  - #{dep.name} (type: #{dep.type})"
  end
else
  puts "  ✅ All dependencies are being used!"
end
puts "\n✅ AI can identify dead code\n\n"

puts "🤖 AI USE CASE 6: Analyzing Impact of Changes"
puts "-" * 80
puts "AI: 'If I change the :db dependency, what routes will be affected?'"
puts
db_dep = app.introspect.dependency(:db)
puts "The :db dependency is used by #{db_dep.used_by_count} routes:"
db_dep.used_by.each do |route|
  puts "  - #{route.verb} #{route.path}"
end
puts "\n✅ AI can perform impact analysis\n\n"

puts "🤖 AI USE CASE 7: Generating Tests"
puts "-" * 80
puts "AI: 'Generate test cases for POST /users'"
puts
route = app.introspect.route("POST", "/users")
if route&.body_schema
  schema_info = app.introspect.schemas.find { |s| s.schema == route.body_schema }
  if schema_info
    puts "Test cases for POST /users:"
    puts
    puts "1. Valid request test:"
    puts "   Input: #{schema_info.example_data.inspect}"
    puts "   Expected: 201 Created"
    puts
    puts "2. Missing required field test:"
    schema_info.required_fields.each do |field|
      data = schema_info.example_data.dup
      data.delete(field)
      puts "   Input (missing #{field}): #{data.inspect}"
      puts "   Expected: 422 Validation Error"
    end
    puts
    puts "3. Invalid type test:"
    puts "   Input: {name: 123, email: 'test@example.com'}"
    puts "   Expected: 422 Validation Error"
  end
end
puts "\n✅ AI can generate comprehensive tests\n\n"

puts "🤖 AI USE CASE 8: Creating Documentation"
puts "-" * 80
puts "AI: 'Generate API documentation in markdown'"
puts
puts "# API Documentation"
puts
puts "## Endpoints"
puts
app.introspect.routes.group_by(&:verb).each do |verb, routes|
  puts "### #{verb} Requests"
  puts
  routes.each do |route|
    puts "#### `#{verb} #{route.path}`"
    puts
    if route.dependencies.any?
      puts "**Dependencies**: #{route.dependencies.map { |d| "`#{d}`" }.join(", ")}"
      puts
    end
    if route.has_body_schema?
      puts "**Request Body**: Required"
      puts
    end
    if route.has_query_schema?
      puts "**Query Parameters**: Supported"
      puts
    end
    if route.has_response_schema?
      puts "**Response**: Validated"
      puts
    end
  end
end
puts "\n## Dependencies"
puts
app.introspect.dependencies.each do |dep|
  puts "- `#{dep.name}`: Used by #{dep.used_by_count} route(s)"
end
puts
puts "✅ AI can auto-generate documentation\n\n"

puts "🤖 AI USE CASE 9: Suggesting Refactorings"
puts "-" * 80
puts "AI: 'What improvements can be made to this codebase?'"
puts
suggestions = []

health = app.introspect.validate
if health[:score] < 0.9
  suggestions << "Health score is #{(health[:score] * 100).round(1)}% - review warnings and issues"
end

most_used = app.introspect.dependencies.most_used(1).first
if most_used && most_used.used_by_count > app.introspect.routes.count * 0.7
  suggestions << "Dependency :#{most_used.name} is used heavily (#{most_used.used_by_count} routes) - consider adding middleware for cross-cutting concerns"
end

routes_without_response = app.introspect.routes.where { |r| !r.has_response_schema? }
if routes_without_response.count > app.introspect.routes.count * 0.3
  suggestions << "#{routes_without_response.count} routes lack response schemas - add them for better validation"
end

schema_with_password = app.introspect.schemas.where_has_field(:password)
if schema_with_password.any?
  schema_with_password.each do |schema|
    if schema.used_as.include?(:response)
      suggestions << "Schema #{schema.name} has password field and is used in responses - use response schema filtering"
    end
  end
end

if suggestions.any?
  puts "Suggestions:"
  suggestions.each { |s| puts "  💡 #{s}" }
else
  puts "  ✅ Code looks good!"
end
puts "\n✅ AI can suggest improvements\n\n"

puts "🤖 AI USE CASE 10: Explaining the Codebase"
puts "-" * 80
puts "AI: 'Explain this application to me'"
puts
puts "This is a #{app.introspect.stats[:routes]}-endpoint API with the following characteristics:"
puts
puts "**Architecture**:"
puts "- #{app.introspect.stats[:verbs].length} HTTP verbs: #{app.introspect.stats[:verbs].join(", ")}"
puts "- #{app.introspect.stats[:dependencies]} dependencies: #{app.introspect.dependencies.names.join(", ")}"
puts "- #{app.introspect.stats[:middleware]} middleware components"
puts "- Schema coverage: #{(app.introspect.stats[:schema_coverage] * 100).round(1)}%"
puts
puts "**Primary Resources**:"
resources = app.introspect.routes.map(&:path)
  .map { |p| p.split("/")[1] }
  .compact
  .uniq
resources.each do |resource|
  resource_routes = app.introspect.routes.search(resource)
  verbs = resource_routes.map(&:verb).uniq.join(", ")
  puts "- #{resource.capitalize}: #{resource_routes.count} endpoint(s) (#{verbs})"
end
puts
puts "**Most Active Dependency**: :#{app.introspect.stats[:most_common_dependency]}"
puts
puts "**Health**: #{(health[:score] * 100).round(1)}% (#{health[:issues].length} issues, #{health[:warnings].length} warnings)"
puts
puts "✅ AI can provide high-level insights\n\n"

puts "=" * 80
puts "✨ All AI use cases demonstrated!"
puts "=" * 80
puts "\nThe introspection API enables AI to:"
puts "  1. ✅ Discover and understand API structure"
puts "  2. ✅ Identify security patterns and gaps"
puts "  3. ✅ Detect inconsistencies and anti-patterns"
puts "  4. ✅ Generate new code from existing patterns"
puts "  5. ✅ Find unused or dead code"
puts "  6. ✅ Analyze impact of changes"
puts "  7. ✅ Generate comprehensive test suites"
puts "  8. ✅ Auto-generate documentation"
puts "  9. ✅ Suggest refactorings and improvements"
puts "  10. ✅ Explain codebases to developers"
puts "=" * 80
puts
