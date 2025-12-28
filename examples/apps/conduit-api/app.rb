# frozen_string_literal: true

require "funapi"
require "funapi/server/falcon"

# Load database configuration
require_relative "config/database"

# Load all models
require_relative "models/user"
require_relative "models/article"
require_relative "models/comment"
require_relative "models/tag"

# Load routes
require_relative "routes/users"
require_relative "routes/profiles"
require_relative "routes/articles"
require_relative "routes/comments"
require_relative "routes/tags"

# Create FunApi application
app = FunApi::App.new(
  title: "Conduit API",
  version: "1.0.0",
  description: "RealWorld Conduit API - A Medium.com clone built with FunApi"
) do |api|
  # Enable CORS for frontend
  api.add_cors(
    allow_origins: ["*"],
    allow_methods: %w[GET POST PUT DELETE OPTIONS],
    allow_headers: %w[Authorization Content-Type]
  )

  # Health check endpoint
  api.get "/api/health" do |_input, _req, _task|
    [{
      status: "ok",
      database: DB.test_connection ? "connected" : "disconnected",
      timestamp: Time.now.iso8601
    }, 200]
  end

  # Register all route modules
  Routes::Users.register(api)
  Routes::Profiles.register(api)
  Routes::Articles.register(api)
  Routes::Comments.register(api)
  Routes::Tags.register(api)

  # Serve static files from frontend/dist for non-API routes
  # This handles the built React frontend
  api.get "/{path:path}" do |input, _req, _task|
    # If it's an API route, it will be handled by the routes above
    # This catch-all serves the React app
    frontend_dir = File.join(__dir__, "frontend", "dist")
    requested_path = input[:path]["path"] || ""

    # Try to serve the requested file
    file_path = File.join(frontend_dir, requested_path)

    if File.file?(file_path)
      # Serve the file with appropriate content type
      content_type = case File.extname(file_path)
      when ".html" then "text/html"
      when ".js" then "application/javascript"
      when ".css" then "text/css"
      when ".json" then "application/json"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".svg" then "image/svg+xml"
      else "application/octet-stream"
      end

      [File.read(file_path), 200, {"Content-Type" => content_type}]
    else
      # For client-side routing, serve index.html
      index_path = File.join(frontend_dir, "index.html")
      if File.file?(index_path)
        [File.read(index_path), 200, {"Content-Type" => "text/html"}]
      else
        ["Frontend not built. Run: cd frontend && npm install && npm run build", 404]
      end
    end
  end
end

# Startup message
puts "=" * 70
puts "Conduit API - RealWorld Example"
puts "=" * 70
puts ""
puts "Starting server on http://localhost:3000"
puts ""
puts "API Endpoints:"
puts "  Authentication:"
puts "    POST   /api/users              - Register"
puts "    POST   /api/users/login        - Login"
puts "    GET    /api/user               - Current user"
puts "    PUT    /api/user               - Update user"
puts ""
puts "  Profiles:"
puts "    GET    /api/profiles/:username           - Get profile"
puts "    POST   /api/profiles/:username/follow    - Follow user"
puts "    DELETE /api/profiles/:username/follow    - Unfollow user"
puts ""
puts "  Articles:"
puts "    GET    /api/articles           - List articles"
puts "    GET    /api/articles/feed      - User feed"
puts "    GET    /api/articles/:slug     - Get article"
puts "    POST   /api/articles           - Create article"
puts "    PUT    /api/articles/:slug     - Update article"
puts "    DELETE /api/articles/:slug     - Delete article"
puts "    POST   /api/articles/:slug/favorite    - Favorite"
puts "    DELETE /api/articles/:slug/favorite    - Unfavorite"
puts ""
puts "  Comments:"
puts "    GET    /api/articles/:slug/comments     - Get comments"
puts "    POST   /api/articles/:slug/comments     - Create comment"
puts "    DELETE /api/articles/:slug/comments/:id - Delete comment"
puts ""
puts "  Tags:"
puts "    GET    /api/tags               - Get all tags"
puts ""
puts "  OpenAPI:"
puts "    GET    /docs                   - Swagger UI"
puts "    GET    /openapi.json           - OpenAPI spec"
puts ""
puts "Database: #{DB.opts[:database]}@#{DB.opts[:host]}"
puts "=" * 70
puts ""

# Start Falcon server
FunApi::Server::Falcon.start(app, port: 3000)
