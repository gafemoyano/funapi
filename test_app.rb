# frozen_string_literal: true

require 'fun_api'
require 'fun_api/server/falcon'

def fetch_user_data(user_id)
  sleep(0.4)
  { id: user_id, name: "User #{user_id}", email: "user#{user_id}@example.com" }
end

def fetch_user_posts(user_id)
  sleep(0.2)
  [
    { id: 1, title: "Post 1 by User #{user_id}", content: 'Content 1' },
    { id: 2, title: "Post 2 by User #{user_id}", content: 'Content 2' }
  ]
end

def fetch_user_stats(_user_id)
  sleep(0.3)
  { posts_count: 2, followers: 42, following: 17 }
end

QuerySchema = FunApi::Schema.define do
  optional(:name).filled(:string)
  optional(:limit).filled(:integer)
end

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

app = FunApi::App.new do |api|
  api.get '/hello', query: QuerySchema do |input, _req|
    name = input[:query][:name] || 'World'
    [{ msg: "Hello from FunApi, #{name}!" }, 200]
  end

  api.get '/users/:id' do |input, _req|
    user_id = input[:path]['id']
    user_data = fetch_user_data(user_id)
    [{ user: user_data }, 200]
  end

  api.post '/users', body: UserCreateSchema, response_schema: UserOutputSchema do |input, _req, _task|
    user_data = input[:body].merge(id: rand(1000))
    [user_data, 201]
  end

  api.get '/dashboard/:id' do |input, _req, task|
    timer_start = Time.now

    user_id = input[:path]['id']

    user_task = task.async { fetch_user_data(user_id) }
    post_task = task.async { fetch_user_posts(user_id) }
    stats_task = task.async { fetch_user_stats(user_id) }

    timer_duration = Time.now - timer_start
    puts "⏱️  Launched async tasks in #{(timer_duration * 1000).round(2)} ms"
    data = {
      user: user_task.wait,
      posts: post_task.wait,
      stats: stats_task.wait
    }

    timer_duration = Time.now - timer_start
    puts "⏱️  Completed all tasks in #{(timer_duration * 1000).round(2)} ms"

    [{ dashboard: data }, 200]
  end

  api.get '/slow/:id' do |input, _req, task|
    user_id = input[:path]['id']

    begin
      data = task.with_timeout(0.5) do
        fetch_user_stats(user_id)
      end
      [{ data: data, message: 'Completed within timeout' }, 200]
    rescue ::Async::TimeoutError
      [{ error: 'Request timed out' }, 408]
    end
  end
end

puts '🚀 Starting FunApi server with async capabilities...'
puts '📍 Try these endpoints:'
puts '   curl http://localhost:3000/hello?name=Ruby'
puts '   curl http://localhost:3000/users/123'
puts '   curl -X POST http://localhost:3000/users -H "Content-Type: application/json" -d \'{"name":"John","email":"john@example.com","password":"secret123"}\''
puts '   # Note: Password will be filtered from response by response_schema'
puts '   curl http://localhost:3000/dashboard/123  # Concurrent execution!'
puts '   curl http://localhost:3000/slow/123       # Timeout example'
puts

FunApi::Server::Falcon.start(app)
