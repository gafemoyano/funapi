# frozen_string_literal: true

require_relative "test_helper"

begin
  require "db/client"
  require "db/postgres"
  DB_POSTGRES_AVAILABLE = true
rescue LoadError
  DB_POSTGRES_AVAILABLE = false
end

begin
  require "testcontainers/postgres"
  TESTCONTAINERS_AVAILABLE = true
rescue LoadError
  TESTCONTAINERS_AVAILABLE = false
end

class TestDbPostgresIntegration < Minitest::Test
  class << self
    attr_accessor :container, :db_client, :using_testcontainers
  end

  def setup
    skip "db-postgres not available" unless DB_POSTGRES_AVAILABLE
    setup_database_connection unless self.class.db_client
    @client = self.class.db_client
  end

  def setup_database_connection
    if ENV["DATABASE_URL"] || ENV["POSTGRES_HOST"]
      setup_from_env
    elsif TESTCONTAINERS_AVAILABLE && docker_available?
      setup_from_testcontainers
    else
      skip "No PostgreSQL connection available (set DATABASE_URL or install testcontainers)"
    end
  end

  def setup_from_env
    host = ENV.fetch("POSTGRES_HOST", "localhost")
    port = ENV.fetch("POSTGRES_PORT", "5432").to_i
    database = ENV.fetch("POSTGRES_DB", "fun_api_test")
    username = ENV.fetch("POSTGRES_USER", "postgres")
    password = ENV.fetch("POSTGRES_PASSWORD", "postgres")

    self.class.db_client = DB::Client.new(
      DB::Postgres::Adapter.new(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password
      )
    )

    verify_connection!
  end

  def setup_from_testcontainers
    self.class.container = Testcontainers::PostgresContainer.new("postgres:14-alpine")
    self.class.container.start
    self.class.using_testcontainers = true

    self.class.db_client = DB::Client.new(
      DB::Postgres::Adapter.new(
        host: self.class.container.host,
        port: self.class.container.first_mapped_port,
        database: self.class.container.database,
        username: self.class.container.username,
        password: self.class.container.password
      )
    )

    verify_connection!
  end

  def verify_connection!
    Sync do
      session = self.class.db_client.session
      session.call("SELECT 1")
      session.close
    end
  rescue => e
    self.class.db_client = nil
    skip "PostgreSQL connection failed: #{e.message}"
  end

  Minitest.after_run do
    if TestDbPostgresIntegration.using_testcontainers && TestDbPostgresIntegration.container
      begin
        TestDbPostgresIntegration.container.stop
      rescue
        nil
      end
      begin
        TestDbPostgresIntegration.container.remove
      rescue
        nil
      end
    end
  end

  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_db_client_as_registered_dependency
    client = @client

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      api.get "/db-version", depends: [:db] do |_input, _req, _task, db:|
        session = db.session
        result = session.call("SELECT VERSION()")
        version = result.to_a.first.first
        session.close
        [{version: version}, 200]
      end
    end

    res = async_request(app, :get, "/db-version")
    assert_equal 200, res.status

    body = JSON.parse(res.body)
    assert body["version"].include?("PostgreSQL")
  end

  def test_db_session_in_lifecycle_hooks
    client = @client
    connected = false
    disconnected = false

    app = FunApi::App.new do |api|
      api.on_startup do
        session = client.session
        session.call("SELECT 1")
        session.close
        connected = true
      end

      api.on_shutdown do
        disconnected = true
      end

      api.get "/" do |_input, _req, _task|
        [{status: "ok"}, 200]
      end
    end

    Async { app.run_startup_hooks }.wait
    assert connected, "Startup hook should have connected to DB"

    app.run_shutdown_hooks
    assert disconnected, "Shutdown hook should have run"
  end

  def test_concurrent_db_queries_with_async_task
    client = @client

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      api.get "/concurrent", depends: [:db] do |_input, _req, task, db:|
        query1 = task.async do
          session = db.session
          result = session.call("SELECT 1 AS num")
          value = result.to_a.first.first
          session.close
          value
        end

        query2 = task.async do
          session = db.session
          result = session.call("SELECT 2 AS num")
          value = result.to_a.first.first
          session.close
          value
        end

        results = [query1.wait, query2.wait]
        [{results: results, sum: results.sum}, 200]
      end
    end

    res = async_request(app, :get, "/concurrent")
    assert_equal 200, res.status

    body = JSON.parse(res.body)
    assert_equal [1, 2], body["results"]
    assert_equal 3, body["sum"]
  end

  def test_db_with_request_validation
    client = @client

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      query_schema = FunApi::Schema.define do
        required(:multiplier).filled(:integer)
      end

      api.get "/calculate", query: query_schema, depends: [:db] do |input, _req, _task, db:|
        multiplier = input[:query][:multiplier]

        session = db.session
        result = session.call("SELECT 5 * #{multiplier.to_i} AS result")
        value = result.to_a.first.first
        session.close
        [{result: value}, 200]
      end
    end

    res = async_request(app, :get, "/calculate?multiplier=10")
    assert_equal 200, res.status

    body = JSON.parse(res.body)
    assert_equal 50, body["result"]
  end

  def test_db_error_handling
    client = @client

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      api.get "/bad-query", depends: [:db] do |_input, _req, _task, db:|
        session = db.session
        begin
          session.call("SELECT * FROM nonexistent_table_xyz")
          [{status: "should not reach"}, 200]
        rescue => e
          raise FunApi::HTTPException.new(
            status_code: 500,
            detail: "Database error: #{e.message}"
          )
        ensure
          session.close
        end
      end
    end

    res = async_request(app, :get, "/bad-query")
    assert_equal 500, res.status

    body = JSON.parse(res.body)
    assert body["detail"].include?("Database error")
  end

  def test_db_connection_pooling_pattern
    client = @client

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      api.get "/pooled", depends: [:db] do |_input, _req, task, db:|
        tasks = 3.times.map do |i|
          task.async do
            session = db.session
            result = session.call("SELECT #{i + 1} AS value")
            value = result.to_a.first.first
            session.close
            value
          end
        end

        values = tasks.map(&:wait)
        [{values: values}, 200]
      end
    end

    res = async_request(app, :get, "/pooled")
    assert_equal 200, res.status

    body = JSON.parse(res.body)
    assert_equal [1, 2, 3], body["values"]
  end

  def test_db_with_response_schema_filtering
    client = @client

    response_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.register(:db) { client }

      api.get "/user/:id", depends: [:db], response_schema: response_schema do |input, _req, _task, db:|
        user_id = input[:path]["id"].to_i

        session = db.session
        result = session.call("SELECT #{user_id} AS id, 'Test User' AS name, 'secret' AS password")
        row = result.to_a.first
        session.close
        [{id: row[0], name: row[1], password: row[2]}, 200]
      end
    end

    res = async_request(app, :get, "/user/42")
    assert_equal 200, res.status

    body = JSON.parse(res.body)
    assert_equal 42, body["id"]
    assert_equal "Test User", body["name"]
    refute body.key?("password"), "password should be filtered by response schema"
  end

  private

  def docker_available?
    system("docker", "info", out: File::NULL, err: File::NULL)
  end
end
