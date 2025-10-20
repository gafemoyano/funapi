# FunApi

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/fun_api`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/fun_api. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/fun_api/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the FunApi project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/fun_api/blob/master/CODE_OF_CONDUCT.md).


```ruby
require 'async/http/internet'

App = FunAPI::App.new do |app|
  app.get "/posts" do |input, req|
    # We're already in a fiber (Falcon manages this)
    # Do concurrent requests
    posts = Async do |task|
      users_task = task.async { fetch_users }
      comments_task = task.async { fetch_comments }

      {
        users: users_task.wait,
        comments: comments_task.wait
      }
    end.wait

    [posts, 200]
  end
end

def fetch_users
  internet = Async::HTTP::Internet.new
  response = internet.get('https://api.example.com/users')
  JSON.parse(response.read)
ensure
  internet&.close
end

# Define route modules
UsersRoutes = ->(app) {
  app.get "/users" do |input, req|
    [User.all, 200]
  end

  app.get "/users/:id" do |input, req|
    [User.find(input[:path]["id"]), 200]
  end
}

PostsRoutes = ->(app) {
  app.get "/posts" do |input, req|
    [Post.all, 200]
  end
}

# Compose app
App = FunAPI::App.new do |app|
  app.use FunAPI::Middleware::Logger

  UsersRoutes.call(app)
  PostsRoutes.call(app)
end
```
