# frozen_string_literal: true

require "funapi"
require "funapi/server/falcon"
require_relative "database"

# Initialize database on startup
init_database!

# Request schemas
TodoCreateSchema = FunApi::Schema.define do
  required(:title).filled(:string)
end

TodoUpdateSchema = FunApi::Schema.define do
  optional(:title).filled(:string)
  optional(:completed).filled(:bool)
end

FilterQuerySchema = FunApi::Schema.define do
  optional(:filter).filled(:string)
end

ToggleAllSchema = FunApi::Schema.define do
  required(:completed).filled(:bool)
end

# FunApi application - Pure JSON API
app = FunApi::App.new(
  title: "TodoMVC API - PostgreSQL Edition",
  version: "1.0.0",
  description: "A TodoMVC JSON API built with FunApi and async PostgreSQL"
) do |api|
  # Serve static files (HTML, CSS, JS)
  api.use Rack::Static,
    urls: ["/public", "/index.html"],
    root: __dir__,
    index: "index.html"

  # CORS for API requests
  api.add_cors(allow_origins: ["*"])

  # Redirect root to index.html
  api.get "/" do |_input, _req, _task|
    [301, {"Location" => "/index.html"}, []]
  end

  # Get all todos (with optional filter)
  api.get "/api/todos", query: FilterQuerySchema do |input, _req, _task|
    filter = input[:query][:filter] || "all"

    todos = case filter
    when "active"
      TodoRepository.active
    when "completed"
      TodoRepository.completed
    else
      TodoRepository.all
    end

    stats = {
      active_count: TodoRepository.active_count,
      completed_count: TodoRepository.completed_count,
      total_count: todos.length
    }

    [{todos: todos, stats: stats}, 200]
  end

  # Create a new todo
  api.post "/api/todos", body: TodoCreateSchema do |input, _req, _task|
    todo = TodoRepository.create(title: input[:body][:title])
    [todo, 201]
  end

  # Get a single todo
  api.get "/api/todos/:id" do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    todo = TodoRepository.find(todo_id)

    raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found") unless todo

    [todo, 200]
  end

  # Update a todo
  api.patch "/api/todos/:id", body: TodoUpdateSchema do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    attrs = {}
    attrs[:completed] = input[:body][:completed] if input[:body].key?(:completed)
    attrs[:title] = input[:body][:title] if input[:body].key?(:title)

    todo = TodoRepository.update(todo_id, attrs)

    raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found") unless todo

    [todo, 200]
  end

  # Delete a todo
  api.delete "/api/todos/:id" do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    deleted = TodoRepository.delete(todo_id)

    raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found") unless deleted

    [{message: "Todo deleted"}, 200]
  end

  # Clear all completed todos
  api.delete "/api/todos/completed/all" do |_input, _req, _task|
    TodoRepository.clear_completed
    [{message: "Completed todos cleared"}, 200]
  end

  # Toggle all todos
  api.post "/api/todos/toggle-all", body: ToggleAllSchema do |input, _req, _task|
    completed = input[:body][:completed]
    TodoRepository.toggle_all(completed)

    todos = TodoRepository.all
    [{todos: todos}, 200]
  end
end

# Startup message
puts "=" * 60
puts "TodoMVC API - PostgreSQL Edition"
puts "=" * 60
puts ""
puts "Starting server on http://localhost:3000"
puts ""
puts "Features:"
puts "  ✓ Pure JSON API (no server-side rendering)"
puts "  ✓ Vanilla JavaScript client"
puts "  ✓ Async PostgreSQL with db-postgres"
puts "  ✓ Full CRUD operations"
puts "  ✓ TodoMVC-compliant UI"
puts ""
puts "Tech Stack:"
puts "  • FunApi (async-first framework)"
puts "  • db-postgres (async PostgreSQL)"
puts "  • Vanilla JavaScript (no frameworks)"
puts "  • Modern CSS"
puts ""
puts "API Endpoints:"
puts "  GET    /api/todos          - List all todos"
puts "  POST   /api/todos          - Create todo"
puts "  GET    /api/todos/:id      - Get todo"
puts "  PATCH  /api/todos/:id      - Update todo"
puts "  DELETE /api/todos/:id      - Delete todo"
puts "  DELETE /api/todos/completed/all - Clear completed"
puts "  POST   /api/todos/toggle-all    - Toggle all"
puts ""
puts "Database: #{DatabaseConfig.from_env[:database]} @ #{DatabaseConfig.from_env[:host]}"
puts "=" * 60
puts ""

# Start server
FunApi::Server::Falcon.start(app, port: 3000)
