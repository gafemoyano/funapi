# frozen_string_literal: true

require "test_helper"
require "funapi/sequel"
require "async/queue"

class TestSequelPool < Minitest::Test
  def with_pool(**options)
    Async do |task|
      db = FunApi::Sequel.connect("mock://", max_connections: 1, pool_timeout: 0.02, **options)
      begin
        task.with_timeout(2) { yield db, task }
      ensure
        db.disconnect
      end
    end.wait
  end

  def test_nested_checkout_reuses_connection
    with_pool do |db, _task|
      db.synchronize do |outer|
        db.synchronize { |inner| assert_same outer, inner }
      end
      assert_equal 1, db.pool.size
    end
  end

  def test_exhaustion_times_out_without_blocking_owner
    with_pool do |db, task|
      db.synchronize do |owner|
        waiter = task.async do
          assert_raises(Sequel::PoolTimeout) { db.synchronize { flunk "pool exceeded capacity" } }
        end
        waiter.wait
        db.synchronize { |nested| assert_same owner, nested }
      end
    end
  end

  def test_in_flight_connect_reserves_capacity_and_survives_disconnect
    gate = Async::Queue.new
    entered = Async::Queue.new
    connections = []
    with_pool(test: false, after_connect: proc { |connection|
      connections << connection
      entered.enqueue(true)
      gate.dequeue
    }) do |db, task|
      holder = task.async { db.synchronize { |connection| connection } }
      entered.dequeue
      assert_equal 1, db.pool.size
      db.disconnect
      assert_equal 1, db.pool.size
      assert_raises(Sequel::PoolTimeout) { db.synchronize { flunk "second connection created" } }
      assert_equal 1, connections.size
      gate.enqueue(true)
      connection = holder.wait
      db.synchronize { |reused| assert_same connection, reused }
    end
  end

  def test_cancelled_waiter_does_not_take_next_connection
    with_pool do |db, task|
      db.synchronize do
        waiter = task.async { db.synchronize { flunk "cancelled waiter acquired connection" } }
        waiter.stop
        assert_equal :stopped, waiter.status
        assert_equal 1, db.pool.size
      end
      db.synchronize { |connection| refute_nil connection }
      assert_equal 1, db.pool.size
    end
  end

  def test_cancelled_holder_returns_connection
    with_pool do |db, task|
      connection = nil
      holder = task.async do
        db.synchronize do |held|
          connection = held
          task.sleep(60)
        end
      end
      holder.stop
      db.synchronize { |reused| assert_same connection, reused }
      assert_equal 1, db.pool.size
    end
  end

  def test_cancelled_connect_releases_reservation
    gate = Async::Queue.new
    started = Async::Queue.new
    attempts = 0
    with_pool(test: false, after_connect: proc { |_connection|
      attempts += 1
      if attempts == 1
        started.enqueue(true)
        gate.dequeue
      end
    }) do |db, task|
      error = nil
      connector = task.async do
        db.synchronize { flunk "cancelled connect completed" }
      rescue Sequel::DatabaseConnectionError => exception
        error = exception
      end
      started.dequeue
      connector.stop
      assert_instance_of Sequel::DatabaseConnectionError, error
      assert_equal 0, db.pool.size
      db.synchronize { |connection| refute_nil connection }
      assert_equal 1, db.pool.size
    end
  end

  def test_disconnect_preserves_checked_out_capacity
    with_pool do |db, task|
      db.synchronize do |held|
        db.disconnect
        assert_equal 1, db.pool.size
        task.async do
          assert_raises(Sequel::PoolTimeout) { db.synchronize { flunk "capacity reset during checkout" } }
        end.wait
        db.synchronize { |nested| assert_same held, nested }
      end
      db.disconnect
      assert_equal 0, db.pool.size
      db.synchronize { |connection| refute_nil connection }
    end
  end

  def test_broken_connection_is_discarded_without_losing_capacity
    with_pool do |db, _task|
      broken = nil
      assert_raises(Sequel::DatabaseDisconnectError) do
        db.synchronize do |connection|
          broken = connection
          raise Sequel::DatabaseDisconnectError
        end
      end
      assert_equal 0, db.pool.size
      db.synchronize { |connection| refute_same broken, connection }
      assert_equal 1, db.pool.size
    end
  end
end
