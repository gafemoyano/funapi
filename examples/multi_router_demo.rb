# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

# This demo simulates a multi-file application. In a real project each router
# below would live in its own file (e.g. `routers/users.rb`, `routers/posts.rb`)
# and be required and composed in the main application file.

IdSchema = FunApi::Schema.define do
  required(:id).filled(:string)
end

UserSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
end

PostSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:title).filled(:string)
end

# ---------------------------------------------------------------------------
# routers/users.rb
# ---------------------------------------------------------------------------
UsersRouter = FunApi::Router.new(prefix: "/users", tags: ["users"], depends: {db: :db}) do |r|
  r.get("/", response_schema: [UserSchema]) do |_input, _req, db:|
    [db[:users], 200]
  end

  r.get("/:id", path: IdSchema, response_schema: UserSchema) do |input, _req, db:|
    user = db[:users].find { |u| u[:id] == input[:path][:id].to_i }
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    [user, 200]
  end
end

# ---------------------------------------------------------------------------
# routers/posts.rb
# ---------------------------------------------------------------------------
PostsRouter = FunApi::Router.new(prefix: "/posts", tags: ["posts"], depends: {db: :db}) do |r|
  r.get("/", response_schema: [PostSchema]) do |_input, _req, db:|
    [db[:posts], 200]
  end

  r.get("/:id", path: IdSchema, response_schema: PostSchema) do |input, _req, db:|
    post = db[:posts].find { |p| p[:id] == input[:path][:id].to_i }
    raise FunApi::HTTPException.new(status_code: 404, detail: "Post not found") unless post

    [post, 200]
  end
end

# ---------------------------------------------------------------------------
# A plain Rack app mounted alongside the FunApi routes.
# ---------------------------------------------------------------------------
LegacyAdmin = lambda do |env|
  body = "Legacy admin panel serving #{env["PATH_INFO"]} (SCRIPT_NAME=#{env["SCRIPT_NAME"]})"
  [200, {"content-type" => "text/plain"}, [body]]
end

# ---------------------------------------------------------------------------
# app.rb — compose everything into one application.
# ---------------------------------------------------------------------------
app = FunApi::App.new(title: "Multi-Router Demo", version: "1.0.0") do |api|
  api.register(:db) do
    {
      users: [{id: 1, name: "Alice"}, {id: 2, name: "Bob"}],
      posts: [{id: 1, title: "Hello"}, {id: 2, title: "World"}]
    }
  end

  api.include_router(UsersRouter)
  api.include_router(PostsRouter)

  api.mount("/admin", LegacyAdmin)
end

puts "Starting server on http://localhost:9292"
puts "Swagger UI (grouped by tag): http://localhost:9292/docs"
puts "Try: /users, /users/1, /posts, /posts/1, /admin/anything"
puts

FunApi::Server::Falcon.start(app, port: 9292)
