# frozen_string_literal: true

require "test_helper"

begin
  require "funapi/sequel"
  SEQUEL_AVAILABLE = true
rescue LoadError
  SEQUEL_AVAILABLE = false
end

begin
  require "testcontainers/postgres"
  TESTCONTAINERS_AVAILABLE = true
rescue LoadError
  TESTCONTAINERS_AVAILABLE = false
end

# Sequel is the blessed data path (see .claude/DECISIONS.md). These tests prove
# the fibered connection pool serves concurrent queries from multiple tasks
# without blocking the reactor, and that FunApi::Model serializes Sequel::Model
# instances through response schemas.
class TestSequelIntegration < Minitest::Test
  class << self
    attr_accessor :container, :db_url
  end

  def setup
    skip "sequel not available" unless SEQUEL_AVAILABLE
    ensure_database
  end

  def ensure_database
    return if self.class.db_url

    if ENV["DATABASE_URL"]
      self.class.db_url = ENV["DATABASE_URL"]
    elsif TESTCONTAINERS_AVAILABLE && docker_available?
      self.class.container = Testcontainers::PostgresContainer.new("postgres:16-alpine")
      self.class.container.start
      self.class.db_url = self.class.container.database_url
    else
      skip "No PostgreSQL available (set DATABASE_URL or install docker + testcontainers)"
    end
  end

  Minitest.after_run do
    if (container = TestSequelIntegration.container)
      begin
        container.stop
        container.remove
      rescue
        nil
      end
    end
  end

  def with_db
    Async do
      db = FunApi::Sequel.connect(self.class.db_url, max_connections: 5)
      begin
        yield db
      ensure
        db.disconnect
      end
    end.wait
  end

  def test_connect_uses_fibered_pool
    with_db do |db|
      assert_instance_of Sequel::FiberedConnectionPool, db.pool
      assert_equal 1, db["SELECT 1 AS one"].first[:one]
    end
  end

  def test_concurrent_queries_through_pool
    with_db do |db|
      results = Async do |task|
        4.times.map do |i|
          task.async do
            db["SELECT pg_sleep(0.05), #{i} AS n"].first[:n]
          end
        end.map(&:wait)
      end.wait

      assert_equal [0, 1, 2, 3], results.sort
    end
  end

  def test_model_serializes_sequel_model_instance
    with_db do |db|
      db.create_table!(:widgets) do
        primary_key :id
        String :name
        String :secret
      end
      db[:widgets].insert(name: "alpha", secret: "s1")
      db[:widgets].insert(name: "beta", secret: "s2")

      widget = Class.new(Sequel::Model(db[:widgets]))
      out = Class.new(FunApi::Model) do
        field :id, :integer
        field :name, :string
      end

      record = widget.first
      dumped = out.dump(record)
      assert_equal({id: 1, name: "alpha"}, dumped)
      refute dumped.key?(:secret), "secret column should be filtered out"
    end
  end

  def test_model_serializes_array_of_sequel_models
    with_db do |db|
      db.create_table!(:items) do
        primary_key :id
        String :name
      end
      db[:items].multi_insert([{name: "a"}, {name: "b"}])

      item = Class.new(Sequel::Model(db[:items]))
      out = Class.new(FunApi::Model) do
        field :id, :integer
        field :name, :string
      end

      dumped = item.order(:id).all.map { |row| out.dump(row) }
      assert_equal [{id: 1, name: "a"}, {id: 2, name: "b"}], dumped
    end
  end

  def test_response_schema_serializes_sequel_model_over_http
    with_db do |db|
      db.create_table!(:users) do
        primary_key :id
        String :name
        String :password
      end
      db[:users].insert(name: "Alice", password: "secret")
      users = Class.new(Sequel::Model(db[:users]))

      user_out = Class.new(FunApi::Model) do
        field :id, :integer
        field :name, :string
      end

      app = FunApi::App.new do |api|
        api.get "/users/:id", response_schema: user_out do |input, _req|
          [users.where(id: input[:path][:id].to_i).first, 200]
        end
      end

      res = Async { Rack::MockRequest.new(app).get("/users/1") }.wait
      assert_equal 200, res.status
      data = JSON.parse(res.body, symbolize_names: true)
      assert_equal "Alice", data[:name]
      refute data.key?(:password)
    end
  end

  private

  def docker_available?
    system("docker", "info", out: File::NULL, err: File::NULL)
  end
end
