require_relative '../lib/fun_api'
require_relative '../lib/fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

app = FunApi::App.new(
  title: 'Middleware Demo API',
  version: '1.0.0',
  description: 'Demonstrating FunApi middleware capabilities'
) do |api|
  api.add_cors(
    allow_origins: ['http://localhost:3000', 'http://127.0.0.1:3000'],
    allow_methods: %w[GET POST PUT DELETE],
    allow_headers: %w[Content-Type Authorization]
  )

  api.add_request_logger

  api.add_trusted_host(
    allowed_hosts: ['localhost', '127.0.0.1', /\.example\.com$/]
  )

  api.get '/' do |_input, _req, _task|
    [{ message: 'Welcome to FunApi Middleware Demo!' }, 200]
  end

  api.get '/health' do |_input, _req, _task|
    [{ status: 'healthy', timestamp: Time.now.to_i }, 200]
  end

  api.post '/users', body: UserSchema do |input, _req, _task|
    user = input[:body].merge(id: rand(1000), created_at: Time.now.to_i)
    [user, 201]
  end

  api.get '/async-demo' do |_input, _req, task|
    result1 = task.async do
      sleep 0.1
      { data: 'from task 1' }
    end
    result2 = task.async do
      sleep 0.1
      { data: 'from task 2' }
    end

    [{ results: [result1.wait, result2.wait] }, 200]
  end
end

puts '🚀 Middleware Demo Server'
puts '=========================='
puts ''
puts 'Enabled Middleware:'
puts '  ✓ CORS (localhost:3000, 127.0.0.1:3000)'
puts '  ✓ Request Logger'
puts '  ✓ Trusted Host'
puts ''
puts 'Endpoints:'
puts '  GET  http://localhost:3000/'
puts '  GET  http://localhost:3000/health'
puts '  POST http://localhost:3000/users'
puts '  GET  http://localhost:3000/async-demo'
puts '  GET  http://localhost:3000/docs (Swagger UI)'
puts ''
puts 'Try:'
puts '  curl http://localhost:3000/'
puts "  curl -X POST http://localhost:3000/users -H 'Content-Type: application/json' -d '{\"name\":\"John\",\"email\":\"john@example.com\"}'"
puts '  curl http://localhost:3000/async-demo'
puts ''

FunApi::Server::Falcon.start(app, port: 3000)
