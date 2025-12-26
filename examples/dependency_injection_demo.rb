# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

FAKE_DB = {
  users: [
    {id: 1, name: "Alice", email: "alice@example.com", role: "admin"},
    {id: 2, name: "Bob", email: "bob@example.com", role: "user"},
    {id: 3, name: "Charlie", email: "charlie@example.com", role: "user"}
  ]
}

class Database
  def self.connect
    new
  end

  def find_user(id)
    FAKE_DB[:users].find { |u| u[:id] == id.to_i }
  end

  def all_users
    FAKE_DB[:users]
  end

  def create_user(attrs)
    id = (FAKE_DB[:users].map { |u| u[:id] }.max || 0) + 1
    user = attrs.merge(id: id)
    FAKE_DB[:users] << user
    user
  end
end

def require_auth
  lambda { |req:|
    token = req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last
    raise FunApi::HTTPException.new(status_code: 401, detail: "Not authenticated") unless token

    user_id = token.to_i
    raise FunApi::HTTPException.new(status_code: 401, detail: "Invalid token") if user_id.zero?

    user_id
  }
end

def get_current_user
  lambda { |db:, user_id: FunApi::Depends(require_auth)|
    user = db.find_user(user_id)
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    user
  }
end

def require_admin
  lambda { |user: FunApi::Depends(get_current_user)|
    raise FunApi::HTTPException.new(status_code: 403, detail: "Admin access required") unless user[:role] == "admin"

    user
  }
end

class Paginator
  def initialize(max_limit: 100)
    @max_limit = max_limit
  end

  def call(input:)
    limit = (input[:query][:limit] || 10).to_i
    offset = (input[:query][:offset] || 0).to_i

    {
      limit: [limit, @max_limit].min,
      offset: [offset, 0].max
    }
  end
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:role).filled(:string)
end

app = FunApi::App.new(
  title: "Dependency Injection Demo",
  version: "1.0.0",
  description: "Demonstrating FunApi dependency injection features"
) do |api|
  api.register(:db) { Database.connect }

  api.register(:logger) do
    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    logger
  end

  api.get "/" do |_input, _req, _task|
    [{
      message: "Dependency Injection Demo API",
      endpoints: {
        public: "GET /",
        users_list: "GET /users",
        user_detail: "GET /users/:id",
        profile: "GET /profile (requires auth)",
        create_user: "POST /users (requires admin)",
        admin: "GET /admin (requires admin)"
      },
      auth: "Use header: Authorization: Bearer <user_id>"
    }, 200]
  end

  api.get "/users",
    query: QuerySchema,
    depends: {
      db: nil,
      page: Paginator.new(max_limit: 50)
    } do |_input, _req, _task, db:, page:|
    users = db.all_users[page[:offset], page[:limit]]

    [{
      users: users,
      pagination: page,
      total: FAKE_DB[:users].length
    }, 200]
  end

  api.get "/users/:id",
    depends: [:db] do |input, _req, _task, db:|
    user = db.find_user(input[:path]["id"])
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    [user, 200]
  end

  api.get "/profile",
    depends: {
      user: get_current_user,
      db: nil
    } do |_input, _req, _task, user:, db:|
    [user, 200]
  end

  api.post "/users",
    body: UserCreateSchema,
    depends: {
      admin: require_admin,
      db: nil,
      logger: nil
    } do |input, _req, _task, admin:, db:, logger:|
    user_data = input[:body]
    user_data[:role] ||= "user"

    new_user = db.create_user(user_data)
    logger.info("Admin #{admin[:name]} created user: #{new_user[:name]}")

    [new_user, 201]
  end

  api.get "/admin",
    depends: {admin: require_admin} do |_input, _req, _task, admin:|
    [{
      message: "Welcome to admin area",
      admin: admin
    }, 200]
  end
end

puts "\n🚀 FunApi Dependency Injection Demo"
puts "=" * 50
puts "\nServer starting on http://localhost:3000"
puts "\n📚 API Docs: http://localhost:3000/docs"
puts "\n✨ Try these commands:\n"
puts "\n# Public endpoint"
puts "curl http://localhost:3000/"
puts "\n# List users (with pagination)"
puts "curl http://localhost:3000/users"
puts "curl 'http://localhost:3000/users?limit=2&offset=0'"
puts "\n# Get specific user"
puts "curl http://localhost:3000/users/1"
puts "\n# Get profile (requires auth)"
puts "curl -H 'Authorization: Bearer 1' http://localhost:3000/profile"
puts "curl -H 'Authorization: Bearer 2' http://localhost:3000/profile"
puts "\n# Admin area (requires admin role)"
puts "curl -H 'Authorization: Bearer 1' http://localhost:3000/admin"
puts "curl -H 'Authorization: Bearer 2' http://localhost:3000/admin  # Should fail (403)"
puts "\n# Create user (requires admin)"
puts "curl -X POST http://localhost:3000/users \\"
puts "  -H 'Authorization: Bearer 1' \\"
puts "  -H 'Content-Type: application/json' \\"
puts "  -d '{\"name\":\"Dave\",\"email\":\"dave@example.com\",\"role\":\"user\"}'"
puts "\n" + ("=" * 50) + "\n\n"

FunApi::Server::Falcon.start(app, port: 3000)
