# frozen_string_literal: true

require_relative "../lib/fun_api"
require_relative "../lib/fun_api/server/falcon"

class DatabaseConnection
  attr_reader :id, :queries_run

  def initialize(id)
    @id = id
    @open = true
    @queries_run = []
    puts "  ✅ Database connection #{id} OPENED"
  end

  def query(sql)
    raise "Connection #{@id} is closed!" unless @open

    @queries_run << sql
    puts "  📊 Running query on connection #{@id}: #{sql}"
    {result: "data for #{sql}"}
  end

  def close
    return unless @open

    @open = false
    puts "  ❌ Database connection #{@id} CLOSED (ran #{@queries_run.length} queries)"
  end

  def open?
    @open
  end
end

$connection_counter = 0
$all_connections = []

app = FunApi::App.new(
  title: "Dependency Cleanup Demo",
  version: "1.0.0"
) do |api|
  api.register(:db) do
    $connection_counter += 1
    conn = DatabaseConnection.new($connection_counter)
    $all_connections << conn

    cleanup = -> { conn.close }

    [conn, cleanup]
  end

  api.get "/" do |_input, _req, _task|
    [{
      message: "Dependency Cleanup Demo",
      endpoints: {
        users: "GET /users (opens db, runs query, closes db)",
        error: "GET /error (opens db, errors, still closes db)",
        multiple: "GET /multiple (opens db once, uses multiple times)"
      },
      stats: "GET /stats"
    }, 200]
  end

  api.get "/users",
    depends: [:db] do |_input, _req, _task, db:|
    puts "\n🔹 Handler executing..."
    users = db.query("SELECT * FROM users")

    puts "🔹 Handler returning response..."
    [users, 200]
  end

  api.get "/error",
    depends: [:db] do |_input, _req, _task, db:|
    puts "\n🔹 Handler executing..."
    db.query("SELECT * FROM users")

    puts "🔹 Handler raising error..."
    raise FunApi::HTTPException.new(status_code: 500, detail: "Something went wrong!")
  end

  api.get "/multiple",
    depends: {
      db1: :db,
      db2: :db
    } do |_input, _req, _task, db1:, db2:|
    puts "\n🔹 Handler executing with multiple deps..."
    puts "  db1 object_id: #{db1.object_id}"
    puts "  db2 object_id: #{db2.object_id}"
    puts "  Same instance? #{db1.equal?(db2)}"

    db1.query("SELECT * FROM users")
    db2.query("SELECT * FROM posts")

    [{
      note: "Both db1 and db2 are the same connection (request-scoped cache)",
      db1_id: db1.id,
      db2_id: db2.id,
      same_instance: db1.equal?(db2)
    }, 200]
  end

  api.get "/stats" do |_input, _req, _task|
    open_count = $all_connections.count(&:open?)
    closed_count = $all_connections.count { |c| !c.open? }

    [{
      total_connections_created: $connection_counter,
      currently_open: open_count,
      closed: closed_count,
      all_connections: $all_connections.map do |c|
        {
          id: c.id,
          open: c.open?,
          queries_run: c.queries_run.length
        }
      end
    }, 200]
  end
end

puts "\n🚀 FunApi Dependency Cleanup Demo"
puts "=" * 50
puts "\nThis demo shows how dependency cleanup works:"
puts "- Dependencies can return [resource, cleanup_proc]"
puts "- Cleanup runs AFTER response is sent (in ensure block)"
puts "- Cleanup runs even if handler raises an error"
puts "- Multiple references to same dependency = single instance"
puts "\nServer starting on http://localhost:3001"
puts "\n✨ Try these commands:\n"
puts "# Open connection, run query, close connection"
puts "curl http://localhost:3001/users"
puts "\n# Open connection, error, still close connection"
puts "curl http://localhost:3001/error"
puts "\n# Open connection once, use multiple times (cached)"
puts "curl http://localhost:3001/multiple"
puts "\n# Check connection stats"
puts "curl http://localhost:3001/stats"
puts "\n" + ("=" * 50) + "\n\n"

FunApi::Server::Falcon.start(app, port: 3001)
