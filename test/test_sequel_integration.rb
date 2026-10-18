# frozen_string_literal: true

require "test_helper"
require "async/queue"

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
    if ENV["REQUIRE_DATABASE"] == "1"
      flunk "sequel is required" unless SEQUEL_AVAILABLE
      flunk "DATABASE_URL is required" if ENV.fetch("DATABASE_URL", "").empty?
    end
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

  def with_db(**options)
    Async do
      db = FunApi::Sequel.connect(self.class.db_url, max_connections: 5, **options)
      begin
        yield db
      ensure
        db.disconnect
      end
    end.wait
  end

  def test_connect_uses_timed_queue_pool
    with_db do |db|
      assert_instance_of Sequel::TimedQueueConnectionPool, db.pool
      assert_equal 1, db["SELECT 1 AS one"].first[:one]
    end
  end

  def test_transactions_commit_and_rollback_on_the_same_connection
    with_db(max_connections: 1, pool_timeout: 0.05) do |db|
      db.create_table!(:pool_transactions) do
        primary_key :id
        String :name
      end

      db.transaction do |connection|
        db.synchronize { |nested| assert_same connection, nested }
        db[:pool_transactions].insert(name: "committed")
        db.transaction(savepoint: true) do
          db[:pool_transactions].insert(name: "savepoint rollback")
          raise Sequel::Rollback
        end
      end

      assert_raises(RuntimeError) do
        db.transaction do
          db[:pool_transactions].insert(name: "outer rollback")
          raise "rollback"
        end
      end
      assert_equal ["committed"], db[:pool_transactions].select_map(:name)
    end
  end

  def test_concurrent_transactions_do_not_share_connections_or_rollback_each_other
    with_db(max_connections: 2) do |db|
      db.create_table!(:pool_concurrent_transactions) do
        primary_key :id
        String :name
      end
      inserted = Async::Queue.new
      release = Async::Queue.new
      rollback_pid = nil
      rollback = Async::Task.current.async do
        db.transaction do
          rollback_pid = db.get(Sequel.function(:pg_backend_pid))
          db[:pool_concurrent_transactions].insert(name: "rolled back")
          inserted.enqueue(true)
          release.dequeue
          raise Sequel::Rollback
        end
      end
      inserted.dequeue
      db.transaction do
        refute_equal rollback_pid, db.get(Sequel.function(:pg_backend_pid))
        assert_empty db[:pool_concurrent_transactions].all
        db[:pool_concurrent_transactions].insert(name: "survives")
      end
      release.enqueue(true)
      rollback.wait
      assert_equal ["survives"], db[:pool_concurrent_transactions].select_map(:name)
    end
  end

  def test_cancelled_transaction_rolls_back_and_connection_is_reusable
    with_db(max_connections: 1) do |db|
      db.create_table!(:pool_cancelled_transactions) do
        primary_key :id
        String :name
      end
      inserted = Async::Queue.new
      holder = Async::Task.current.async do |task|
        db.transaction do
          db[:pool_cancelled_transactions].insert(name: "cancelled")
          inserted.enqueue(true)
          task.sleep(60)
        end
      end
      inserted.dequeue
      holder.stop
      assert_empty db[:pool_cancelled_transactions].all
      db.transaction { db[:pool_cancelled_transactions].insert(name: "reused") }
      assert_equal ["reused"], db[:pool_cancelled_transactions].select_map(:name)
      assert_equal 1, db.pool.size
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
