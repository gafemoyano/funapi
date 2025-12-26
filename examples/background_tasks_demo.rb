# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"
require "logger"

FAKE_EMAILS = []
FAKE_LOGS = []
FAKE_WEBHOOKS = []

def send_welcome_email(email, name)
  sleep 0.05
  message = "Welcome email sent to #{email} for #{name}"
  FAKE_EMAILS << message
  puts "  📧 #{message}"
end

def log_signup_event(user_id, email)
  sleep 0.02
  log_entry = "[#{Time.now}] User #{user_id} signed up: #{email}"
  FAKE_LOGS << log_entry
  puts "  📝 #{log_entry}"
end

def notify_admin(user_count)
  sleep 0.03
  notification = "Admin notified: Total users now #{user_count}"
  FAKE_WEBHOOKS << notification
  puts "  🔔 #{notification}"
end

def send_webhook(url, data)
  sleep 0.04
  webhook = "Webhook sent to #{url}: #{data}"
  FAKE_WEBHOOKS << webhook
  puts "  🌐 #{webhook}"
end

USERS_DB = []

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:notifications).filled(:bool)
end

app = FunApi::App.new(
  title: "Background Tasks Demo API",
  version: "1.0.0",
  description: "Demonstrating background tasks in FunApi"
) do |api|
  api.register(:logger) do
    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    logger
  end

  api.get "/" do |_input, _req, _task|
    [{
      message: "Background Tasks Demo API",
      endpoints: {
        home: "GET /",
        signup: "POST /signup (body: {name, email, notifications?})",
        users: "GET /users",
        send_batch: "POST /send-batch-emails",
        stats: "GET /stats"
      },
      info: "Background tasks run after response is sent but before dependencies close"
    }, 200]
  end

  api.post "/signup", body: UserSchema do |input, _req, _task, background:|
    user_data = input[:body]

    user_id = USERS_DB.size + 1
    user = user_data.merge(id: user_id, created_at: Time.now.to_s)
    USERS_DB << user

    puts "\n🚀 Handler: Creating user #{user[:name]}"

    background.add_task(method(:send_welcome_email), user[:email], user[:name])
    background.add_task(method(:log_signup_event), user_id, user[:email])

    background.add_task(method(:notify_admin), USERS_DB.size) if user[:notifications]

    background.add_task(
      method(:send_webhook),
      "https://api.example.com/hooks/user-created",
      user.to_json
    )

    puts "✅ Handler: Response ready (user created)\n"

    [{user: user, message: "Signup successful! Check your email."}, 201]
  end

  api.get "/users" do |_input, _req, _task|
    [{users: USERS_DB, count: USERS_DB.size}, 200]
  end

  api.post "/send-batch-emails", depends: [:logger] do |_input, _req, _task, logger:, background:|
    user_count = USERS_DB.size

    return [{error: "No users to email"}, 400] if user_count.zero?

    puts "\n🚀 Handler: Queueing #{user_count} email tasks"

    USERS_DB.each do |user|
      background.add_task(lambda { |email, name|
        logger.info("Sending batch email to #{email}")
        send_welcome_email(email, name)
      }, user[:email], user[:name])
    end

    puts "✅ Handler: Response ready (#{user_count} emails queued)\n"

    [{message: "#{user_count} emails queued for sending", count: user_count}, 200]
  end

  api.get "/stats" do |_input, _req, _task|
    [{
      users: USERS_DB.size,
      emails_sent: FAKE_EMAILS.size,
      logs_created: FAKE_LOGS.size,
      webhooks_sent: FAKE_WEBHOOKS.size
    }, 200]
  end
end

puts "\n🚀 FunApi Background Tasks Demo"
puts "=" * 60
puts "\nServer starting on http://localhost:3000"
puts "\n📚 API Docs: http://localhost:3000/docs"
puts "\n✨ Try these examples:\n"
puts "\n# Check available endpoints"
puts "curl http://localhost:3000/"
puts "\n# Sign up a user (watch background tasks execute)"
puts "curl -X POST http://localhost:3000/signup \\"
puts "  -H 'Content-Type: application/json' \\"
puts "  -d '{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"notifications\":true}'"
puts "\n# Sign up another user"
puts "curl -X POST http://localhost:3000/signup \\"
puts "  -H 'Content-Type: application/json' \\"
puts "  -d '{\"name\":\"Bob\",\"email\":\"bob@example.com\",\"notifications\":false}'"
puts "\n# Send batch emails to all users"
puts "curl -X POST http://localhost:3000/send-batch-emails"
puts "\n# Check stats"
puts "curl http://localhost:3000/stats"
puts "\n# List all users"
puts "curl http://localhost:3000/users"
puts "\n" + ("=" * 60)
puts "\n💡 Notice how:"
puts "  - Response is sent IMMEDIATELY"
puts "  - Background tasks run AFTER handler completes"
puts "  - Background tasks run BEFORE dependencies close"
puts "  - Multiple tasks execute in order"
puts "  - Tasks can access dependencies (logger, db, etc.)\n\n"

FunApi::Server::Falcon.start(app, port: 3000)
