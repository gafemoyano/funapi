require_relative "lib/funapi"
require_relative "lib/funapi/server/falcon"

class SimpleMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    puts "[SimpleMiddleware] Before request"
    status, headers, body = @app.call(env)
    puts "[SimpleMiddleware] After request - Status: #{status}"
    headers["X-Simple-Middleware"] = "true"
    [status, headers, body]
  end
end

class LoggingMiddleware
  def initialize(app, prefix = "LOG")
    @app = app
    @prefix = prefix
  end

  def call(env)
    request = Rack::Request.new(env)
    puts "[#{@prefix}] #{request.request_method} #{request.path}"
    @app.call(env)
  end
end

app = FunApi::App.new(
  title: "Middleware Test API",
  version: "1.0.0"
) do |api|
  api.use SimpleMiddleware
  api.use LoggingMiddleware, "ACCESS"

  api.get "/test" do |_input, _req, _task|
    [{message: "Middleware test successful!"}, 200]
  end

  api.get "/hello/:name" do |input, _req, _task|
    name = input[:path]["name"]
    [{greeting: "Hello, #{name}!"}, 200]
  end
end

puts "Starting FunApi with middleware..."
puts "Test endpoints:"
puts "  http://localhost:3000/test"
puts "  http://localhost:3000/hello/World"
puts "  http://localhost:3000/docs"
puts ""

FunApi::Server::Falcon.start(app, port: 3000)
