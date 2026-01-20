# frozen_string_literal: true

# Quick manual test to verify introspection works
require_relative '../lib/fun_api'

puts "\n✅ MANUAL INTROSPECTION TEST\n\n"

# Create a simple app
TestSchema = FunApi::Schema.define do
  required(:name).filled(:string)
end

app = FunApi::App.new do |api|
  api.register(:db) { {} }

  api.get '/test', depends: [:db] do |_input, _req, _task, db:|
    [{}, 200]
  end

  api.post '/test', body: TestSchema, depends: [:db] do |input, _req, _task, db:|
    [input[:body], 201]
  end
end

# Test 1: Basic introspection works
puts "1. app.introspect exists: #{app.respond_to?(:introspect)}"
puts "2. Routes count: #{app.introspect.routes.count}"
puts "3. Dependencies count: #{app.introspect.dependencies.count}"
puts "4. Can query routes: #{app.introspect.routes.where_verb('GET').count} GET routes"
puts "5. Can find dependency usage: :db used by #{app.introspect.dependency(:db).used_by_count} routes"
puts "6. Stats work: #{app.introspect.stats.keys.include?(:routes)}"
puts "7. JSON export works: #{JSON.parse(app.introspect.to_json).keys.include?('routes')}"
puts "8. Health check works: Score = #{(app.introspect.validate[:score] * 100).round}%"

puts "\n✅ All manual tests passed!"
