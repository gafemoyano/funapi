# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

DB = {connected: false, users: []}
CACHE = {warmed: false}

app = FunApi::App.new(
  title: "Lifecycle Demo",
  version: "1.0.0"
) do |api|
  api.on_startup do
    puts "Connecting to database..."
    sleep 0.1
    DB[:connected] = true
    DB[:users] = [{id: 1, name: "Alice"}, {id: 2, name: "Bob"}]
    puts "Database connected!"
  end

  api.on_startup do
    puts "Warming cache..."
    sleep 0.05
    CACHE[:warmed] = true
    puts "Cache warmed!"
  end

  api.on_shutdown do
    puts "Closing database connection..."
    DB[:connected] = false
    puts "Database disconnected!"
  end

  api.on_shutdown do
    puts "Clearing cache..."
    CACHE[:warmed] = false
    puts "Cache cleared!"
  end

  api.get "/status" do |_input, _req, _task|
    [{
      db_connected: DB[:connected],
      cache_warmed: CACHE[:warmed]
    }, 200]
  end

  api.get "/users" do |_input, _req, _task|
    [DB[:users], 200]
  end
end

puts "Starting Lifecycle Demo..."
puts "Try: curl http://localhost:3000/status"
puts "Try: curl http://localhost:3000/users"
puts ""

FunApi::Server::Falcon.start(app, port: 3000)
