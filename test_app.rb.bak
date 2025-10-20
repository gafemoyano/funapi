# frozen_string_literal: true

require 'fun_api'
require 'fun_api/server/falcon'

# Simulate async data fetching
def fetch_user_data(user_id)
  sleep(0.1) # Simulate network delay
  { id: user_id, name: "User #{user_id}", email: "user#{user_id}@example.com" }
end

def fetch_user_posts(user_id)
  sleep(0.15) # Simulate network delay
  [
    { id: 1, title: "Post 1 by User #{user_id}", content: 'Content 1' },
    { id: 2, title: "Post 2 by User #{user_id}", content: 'Content 2' }
  ]
end

def fetch_user_stats(_user_id)
  sleep(0.2) # Simulate network delay
  { posts_count: 2, followers: 42, following: 17 }
end

# Build the application
app = FunApi::App.new do |api|
  # Simple async route
  api.get '/hello' do |input, _req|
    name = input[:query]['name'] || 'World'
    [{ msg: "Hello from FunApi, #{name}!" }, 200]
  end

  # Route with path params
  api.get '/users/:id' do |input, _req|
    user_id = input[:path]['id']
    user_data = fetch_user_data(user_id)
    [{ user: user_data }, 200]
  end

  # Concurrent execution example
  api.get '/dashboard/:id' do |input, _req|
    user_id = input[:path]['id']

    # This will execute all three operations concurrently!
    data = concurrent(
      user: -> { fetch_user_data(user_id) },
      posts: -> { fetch_user_posts(user_id) },
      stats: -> { fetch_user_stats(user_id) }
    )

    [{ dashboard: data }, 200]
  end

  # Timeout example
  api.get '/slow/:id' do |input, _req|
    user_id = input[:path]['id']

    begin
      # This will timeout after 0.5 seconds
      data = timeout(0.5) do
        fetch_user_stats(user_id) # This takes 0.2s, so it should succeed
      end
      [{ data: data, message: 'Completed within timeout' }, 200]
    rescue ::Async::TimeoutError
      [{ error: 'Request timed out' }, 408]
    end
  end

  # Advanced concurrent example with block syntax
  api.get '/advanced/:id' do |input, _req|
    user_id = input[:path]['id']

    results = concurrent_block do |task|
      # Start multiple operations
      user_task = task.async { fetch_user_data(user_id) }
      posts_task = task.async { fetch_user_posts(user_id) }

      # Get user data first
      user = user_task.wait

      # Then start stats based on user data
      stats_task = task.async { fetch_user_stats(user[:id]) }

      {
        user: user,
        posts: posts_task.wait,
        stats: stats_task.wait
      }
    end

    [{ advanced: results }, 200]
  end
end

puts '🚀 Starting FunApi server with async capabilities...'
puts '📍 Try these endpoints:'
puts '   curl http://localhost:3000/hello?name=Ruby'
puts '   curl http://localhost:3000/users/123'
puts '   curl http://localhost:3000/dashboard/123  # Concurrent execution!'
puts '   curl http://localhost:3000/slow/123       # Timeout example'
puts '   curl http://localhost:3000/advanced/123   # Advanced async'
puts

FunApi::Server::Falcon.start(app)
