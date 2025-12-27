# frozen_string_literal: true

require_relative "../../../lib/funapi"
require_relative "../../../lib/fun_api/templates"
require_relative "../../../lib/funapi/server/falcon"
require_relative "./database"

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

# Templates setup
templates = FunApi::Templates.new(
  directory: File.join(__dir__, "templates"),
  layout: "layout.html.erb"
)

# FunApi application
app = FunApi::App.new(
  title: "TodoMVC - FunApi Edition",
  version: "1.0.0",
  description: "A classic TodoMVC application built with FunApi, Sequel, and HTMX"
) do |api|
  # Serve static files (CSS, JS)
  api.use Rack::Static,
    urls: ["/public"],
    root: __dir__

  # Main page - list todos with optional filter
  api.get "/", query: FilterQuerySchema do |input, _req, _task|
    filter = input[:query]["filter"] || "all"

    todos = case filter
            when "active"
              TodoRepository.active
            when "completed"
              TodoRepository.completed
            else
              TodoRepository.all
            end

    templates.response("index.html.erb",
      title: "todos",
      todos: todos,
      filter: filter,
      active_count: TodoRepository.active_count,
      completed_count: TodoRepository.completed_count)
  end

  # Create a new todo
  api.post "/todos", body: TodoCreateSchema do |input, _req, _task|
    todo = TodoRepository.create(title: input[:body][:title])

    templates.response("_todo.html.erb",
      layout: false,
      todo: todo,
      status: 201)
  end

  # Update a todo (toggle completion or edit title)
  api.patch "/todos/:id", body: TodoUpdateSchema do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    attrs = {}
    attrs[:completed] = input[:body][:completed] if input[:body].key?(:completed)
    attrs[:title] = input[:body][:title] if input[:body].key?(:title)

    todo = TodoRepository.update(todo_id, attrs)

    unless todo
      raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found")
    end

    templates.response("_todo.html.erb",
      layout: false,
      todo: todo)
  end

  # Delete a todo
  api.delete "/todos/:id" do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    deleted = TodoRepository.delete(todo_id)

    unless deleted
      raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found")
    end

    FunApi::TemplateResponse.new("", status: 200)
  end

  # Clear all completed todos
  api.delete "/todos/clear-completed" do |_input, _req, _task|
    TodoRepository.clear_completed
    FunApi::TemplateResponse.new("", status: 200)
  end

  # Toggle all todos
  api.patch "/todos/toggle-all" do |input, _req, _task|
    # If any active todos exist, mark all as complete; otherwise mark all as incomplete
    all_completed = TodoRepository.active_count.zero?
    TodoRepository.toggle_all(!all_completed)

    # Return updated todo list
    todos = TodoRepository.all
    html = todos.map { |todo| templates.render("_todo.html.erb", layout: false, todo: todo) }.join

    FunApi::TemplateResponse.new(html, status: 200)
  end

  # JSON API endpoint (bonus - for testing)
  api.get "/api/todos" do |_input, _req, _task|
    todos = TodoRepository.all.map(&:to_hash)
    [todos, 200]
  end
end

# Startup message
puts "=" * 60
puts "TodoMVC - FunApi Edition"
puts "=" * 60
puts ""
puts "Starting server on http://localhost:3000"
puts ""
puts "Features:"
puts "  ✓ Create todos"
puts "  ✓ Toggle completion"
puts "  ✓ Edit todos (double-click)"
puts "  ✓ Delete todos"
puts "  ✓ Filter (All / Active / Completed)"
puts "  ✓ Clear completed"
puts "  ✓ Toggle all"
puts ""
puts "Tech Stack:"
puts "  • FunApi (async-first framework)"
puts "  • Sequel ORM + SQLite"
puts "  • HTMX (reactive updates)"
puts "  • Vanilla JS (editing + keyboard shortcuts)"
puts ""
puts "JSON API also available at /api/todos"
puts "=" * 60
puts ""

# Start server
FunApi::Server::Falcon.start(app, port: 3000)
