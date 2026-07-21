# frozen_string_literal: true

require "fileutils"

module FunApi
  class CLI
    module Templates
      module_function

      def write_all(target, title)
        FileUtils.mkdir_p(target)
        FileUtils.mkdir_p(File.join(target, "test"))

        write(target, "app.rb", app_rb(title))
        write(target, "config.ru", config_ru)
        write(target, "Gemfile", gemfile)
        write(target, "AGENTS.md", agents_md(title))
        write(target, "README.md", readme(title))
        write(target, ".gitignore", gitignore)
        write(target, "test/test_helper.rb", test_helper)
        write(target, "test/app_test.rb", app_test)
      end

      def write(target, relative, contents)
        path = File.join(target, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, contents)
      end

      def app_rb(title)
        <<~RUBY
          # frozen_string_literal: true

          require "funapi"

          # A FunApi::Model *is* your schema: one declaration gives request
          # validation, response serialization/filtering, and OpenAPI docs.
          # Visit /docs (Swagger UI) once the server is running.
          class CreateWidget < FunApi::Model
            field :name, :string
            field :quantity, :integer, default: 1, min: 0
          end

          class Widget < FunApi::Model
            field :id, :integer
            field :name, :string
            field :quantity, :integer
          end

          # The application is exposed as the `Application` constant so config.ru,
          # `funapi dev`, and your tests can all reach it.
          Application = FunApi::App.new(
            title: "#{title}",
            version: "0.1.0",
            description: "A FunApi application"
          ) do |api|
            # Handlers receive |input, req| and return [payload, status].
            api.get "/" do |_input, _req|
              [{message: "Welcome to #{title}. Visit /docs for interactive API docs."}, 200]
            end

            api.get "/hello/:name" do |input, _req|
              [{message: "Hello, \#{input[:path][:name]}!"}, 200]
            end

            api.post "/widgets", body: CreateWidget, response_schema: Widget do |input, _req|
              widget = {id: rand(1000), name: input[:body][:name], quantity: input[:body][:quantity]}
              [widget, 201]
            end
          end
        RUBY
      end

      def config_ru
        <<~RUBY
          # frozen_string_literal: true

          require_relative "app"

          run Application
        RUBY
      end

      def gemfile
        <<~RUBY
          # frozen_string_literal: true

          source "https://rubygems.org"

          gem "funapi"
          gem "falcon"

          # Database (optional): FunApi blesses Sequel with a fibered pool.
          # Uncomment and run `bundle install` to use Postgres.
          # gem "sequel"
          # gem "pg"

          group :development, :test do
            gem "minitest"
            gem "rake"
          end
        RUBY
      end

      def gitignore
        <<~TEXT
          /.bundle/
          /vendor/bundle/
          /tmp/
          /log/
          *.gem
          .env
        TEXT
      end

      def test_helper
        <<~RUBY
          # frozen_string_literal: true

          require "funapi"
          require "funapi/test_client"
          require "minitest/autorun"

          require_relative "../app"
        RUBY
      end

      def app_test
        <<~RUBY
          # frozen_string_literal: true

          require_relative "test_helper"

          # FunApi::TestClient wraps the Rack interface and handles the async
          # reactor for you — no server boot, no `Async { }.wait` in your tests.
          class AppTest < Minitest::Test
            def client
              @client ||= FunApi::TestClient.new(Application)
            end

            def test_root
              res = client.get("/")
              assert_equal 200, res.status
            end

            def test_hello_uses_path_param
              res = client.get("/hello/Ada")
              assert_equal "Hello, Ada!", res.json[:message]
            end

            def test_create_widget_applies_defaults
              res = client.post("/widgets", json: {name: "Sprocket"})
              assert_equal 201, res.status
              assert_equal "Sprocket", res.json[:name]
              assert_equal 1, res.json[:quantity]
            end

            def test_create_widget_validates
              res = client.post("/widgets", json: {})
              assert_equal 422, res.status
            end
          end
        RUBY
      end

      def readme(title)
        <<~MARKDOWN
          # #{title}

          A [FunApi](https://github.com/gafemoyano/funapi) application — a minimal,
          async-first Ruby web framework inspired by FastAPI.

          ## Setup

          ```bash
          bundle install
          ```

          ## Run

          ```bash
          funapi dev            # boots Falcon with code reloading
          ```

          Then open:

          - http://localhost:3000/          — the app
          - http://localhost:3000/docs      — interactive Swagger UI
          - http://localhost:3000/openapi.json — the OpenAPI spec

          ## Routes

          ```bash
          funapi routes         # human-readable route table
          funapi routes --json  # machine-readable
          ```

          ## Test

          ```bash
          ruby -Itest test/app_test.rb
          ```

          Tests use `FunApi::TestClient`, which drives the app through the Rack
          interface without booting a server.
        MARKDOWN
      end

      def agents_md(title)
        <<~MARKDOWN
          # #{title} — Agent Instructions

          This is a [FunApi](https://github.com/gafemoyano/funapi) application: a
          minimal, async-first Ruby web framework inspired by FastAPI. This file
          orients AI coding agents working in this repo.

          ## Commands

          ```bash
          bundle install                    # install dependencies
          funapi dev                        # run locally with code reloading (http://localhost:3000)
          funapi routes                     # list routes (add --json for machine output)
          ruby -Itest test/app_test.rb      # run the test suite
          ```

          ## Architecture

          - `app.rb` — defines models and the `Application` (a `FunApi::App`). This
            is the heart of the app.
          - `config.ru` — Rack entry point; `require_relative "app"` then `run Application`.
          - `test/` — Minitest tests using `FunApi::TestClient`.

          ## Route handlers

          Handlers receive two arguments and return `[payload, status]`:

          ```ruby
          api.get "/widgets/:id" do |input, req|
            # input[:path]    => { id: "..." }   (symbol keys, string values)
            # input[:query]   => query params
            # input[:body]    => parsed & validated body
            # input[:headers] => downcased header hash
            [{id: input[:path][:id]}, 200]
          end
          ```

          Never reach for a task object in a handler. For concurrency use
          `FunApi.async { ... }` and `FunApi.sleep(n)` (non-blocking).

          ## Models are schemas

          A `FunApi::Model` gives validation, serialization, and OpenAPI from one
          declaration. Pass a model to `body:`, `query:`, `path:`, or
          `response_schema:` (use `[Model]` for a collection):

          ```ruby
          class CreateWidget < FunApi::Model
            field :name, :string
            field :quantity, :integer, default: 1, min: 0
          end

          api.post "/widgets", body: CreateWidget, response_schema: Widget do |input, req|
            [create_widget(input[:body]), 201]  # response filtered by Widget
          end
          ```

          Validation failures return a `422` with a FastAPI-style `detail` array.
          `response_schema` filters out any field not declared (e.g. passwords).

          ## Streaming

          Return a `FunApi::StreamingResponse` for chunked output or
          `FunApi::SSE.response` for Server-Sent Events:

          ```ruby
          api.get "/events" do |_input, _req|
            FunApi::SSE.response do |sse|
              sse.send(data: {tick: 1}, event: "tick")
            end
          end
          ```

          ## Dependency injection

          Register request-scoped dependencies and inject them by keyword:

          ```ruby
          api.register(:db) { Database.connect }
          api.get "/widgets", depends: [:db] do |input, req, db:|
            [db.widgets, 200]
          end
          ```

          In tests, swap them: `Application.override_dependency(:db, FakeDb.new)`
          and `Application.reset_overrides!`.

          ## Testing

          Use `FunApi::TestClient` — it handles the async reactor internally:

          ```ruby
          client = FunApi::TestClient.new(Application)
          res = client.post("/widgets", json: {name: "Sprocket"})
          res.status      # => 201
          res.json        # => { id: ..., name: "Sprocket", quantity: 1 }  (symbol keys)
          ```

          ## Conventions

          - Ruby >= 3.2, frozen string literals.
          - Keep handlers thin; put validation in models.
          - Run the tests before committing.
        MARKDOWN
      end
    end
  end
end
