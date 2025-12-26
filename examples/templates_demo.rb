# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/fun_api/templates"
require_relative "../lib/funapi/server/falcon"

TODOS = [
  {id: 1, title: "Learn FunApi", completed: true},
  {id: 2, title: "Build something with HTMX", completed: false},
  {id: 3, title: "Deploy to production", completed: false}
]

TodoSchema = FunApi::Schema.define do
  required(:title).filled(:string)
end

templates = FunApi::Templates.new(
  directory: File.join(__dir__, "templates"),
  layout: "layouts/application.html.erb"
)

app = FunApi::App.new(
  title: "HTMX Todo Demo",
  version: "1.0.0",
  description: "A simple todo app demonstrating FunApi templates with HTMX"
) do |api|
  api.get "/" do |_input, _req, _task|
    templates.response("todos/index.html.erb",
      title: "Todo List",
      todos: TODOS)
  end

  api.post "/todos", body: TodoSchema do |input, _req, _task|
    new_id = (TODOS.map { |t| t[:id] }.max || 0) + 1
    todo = {
      id: new_id,
      title: input[:body][:title],
      completed: false
    }
    TODOS << todo

    templates.response("todos/_todo.html.erb",
      layout: false,
      todo: todo,
      status: 201)
  end

  api.patch "/todos/:id/toggle" do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    todo = TODOS.find { |t| t[:id] == todo_id }

    unless todo
      raise FunApi::HTTPException.new(status_code: 404, detail: "Todo not found")
    end

    todo[:completed] = !todo[:completed]

    templates.response("todos/_todo.html.erb",
      layout: false,
      todo: todo)
  end

  api.delete "/todos/:id" do |input, _req, _task|
    todo_id = input[:path]["id"].to_i
    TODOS.reject! { |t| t[:id] == todo_id }

    FunApi::TemplateResponse.new("")
  end

  api.get "/api/todos" do |_input, _req, _task|
    [TODOS, 200]
  end
end

puts "Starting HTMX Todo Demo..."
puts "Open http://localhost:3000 in your browser"
puts ""
puts "Features:"
puts "  - Add todos with the form"
puts "  - Toggle completion with 'Done' button"
puts "  - Delete todos with 'Delete' button"
puts "  - All updates happen without page reload (HTMX)"
puts ""
puts "JSON API also available at /api/todos"
puts ""

FunApi::Server::Falcon.start(app, port: 3000)
