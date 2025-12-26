---
title: Background Tasks
---

# Background Tasks

Execute tasks after the response is sent to the client.

## Basic Usage

Request the `background:` parameter in your handler:

```ruby
api.post '/signup', body: UserSchema do |input, req, task, background:|
  user = create_user(input[:body])
  
  # These run AFTER the response is sent
  background.add_task(method(:send_welcome_email), user[:email])
  background.add_task(method(:log_signup), user[:id])
  
  [{ user: user }, 201]
end
```

The client receives the response immediately. The tasks execute afterward.

## Adding Tasks

### With Method References

```ruby
def send_email(to, subject)
  # send email
end

background.add_task(method(:send_email), "user@example.com", "Welcome!")
```

### With Lambdas

```ruby
background.add_task(->(email) { Mailer.send(email) }, user[:email])
```

### With Keyword Arguments

```ruby
background.add_task(
  ->(to:, subject:) { send_email(to: to, subject: subject) },
  to: "user@example.com",
  subject: "Welcome!"
)
```

## With Dependencies

Dependencies are available to background tasks:

```ruby
api.register(:mailer) { Mailer.new }
api.register(:analytics) { Analytics.new }

api.post '/signup', depends: [:mailer, :analytics] do |input, req, task, mailer:, analytics:, background:|
  user = create_user(input[:body])
  
  # Dependencies captured in closure
  background.add_task(lambda {
    mailer.send_welcome(user[:email])
    analytics.track('signup', user[:id])
  })
  
  [{ user: user }, 201]
end
```

## Error Handling

Background task errors are logged but don't affect the response:

```ruby
background.add_task(lambda {
  raise "Task failed!"
  # Logged as warning, doesn't crash the server
})
```

## When to Use

**Good for:**
- Email notifications
- Logging and analytics
- Cache warming
- Simple webhook calls
- Audit trail recording

**Not for:**
- Long-running jobs (> 30 seconds)
- Jobs requiring persistence
- Jobs that must survive restarts
- Jobs needing retries

For complex jobs, use a proper job queue like Sidekiq or GoodJob.

## Complete Example

```ruby
require 'funapi'
require 'funapi/server/falcon'

def send_welcome_email(email)
  puts "Sending welcome email to #{email}"
  # Actually send email
end

def log_signup(user_id)
  puts "Logging signup for user #{user_id}"
  # Log to analytics
end

def notify_admin(user)
  puts "Notifying admin about new user: #{user[:name]}"
  # Send Slack notification
end

app = FunApi::App.new do |api|
  UserSchema = FunApi::Schema.define do
    required(:name).filled(:string)
    required(:email).filled(:string)
  end

  api.post '/signup', body: UserSchema do |input, req, task, background:|
    user = { id: rand(1000), **input[:body] }
    
    background.add_task(method(:send_welcome_email), user[:email])
    background.add_task(method(:log_signup), user[:id])
    background.add_task(method(:notify_admin), user)
    
    [{ user: user, message: 'Check your email!' }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```
