# frozen_string_literal: true

require "db/client"
require "db/postgres"

# PostgreSQL connection configuration
module DatabaseConfig
  def self.from_env
    {
      host: ENV.fetch("POSTGRES_HOST", "localhost"),
      port: ENV.fetch("POSTGRES_PORT", "5432").to_i,
      database: ENV.fetch("POSTGRES_DB", "todos"),
      username: ENV.fetch("POSTGRES_USER", "postgres"),
      password: ENV.fetch("POSTGRES_PASSWORD", "postgres")
    }
  end

  def self.client
    @client ||= DB::Client.new(
      DB::Postgres::Adapter.new(**from_env)
    )
  end
end

# Initialize database schema
def init_database!
  Sync do
    session = DatabaseConfig.client.session

    # Create todos table if it doesn't exist
    session.call(<<~SQL)
      CREATE TABLE IF NOT EXISTS todos (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        completed BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      )
    SQL

    session.close
  end

  puts "Database initialized successfully"
rescue => e
  puts "Database initialization failed: #{e.message}"
  puts "Make sure PostgreSQL is running and accessible"
  puts "Connection: #{DatabaseConfig.from_env.inspect}"
  exit 1
end

# Todo repository for async database operations
module TodoRepository
  extend self

  def all
    session = DatabaseConfig.client.session
    result = session.call("SELECT * FROM todos ORDER BY created_at ASC")
    todos = result.to_a.map { |row| row_to_hash(row) }
    session.close
    todos
  end

  def active
    session = DatabaseConfig.client.session
    result = session.call("SELECT * FROM todos WHERE completed = FALSE ORDER BY created_at ASC")
    todos = result.to_a.map { |row| row_to_hash(row) }
    session.close
    todos
  end

  def completed
    session = DatabaseConfig.client.session
    result = session.call("SELECT * FROM todos WHERE completed = TRUE ORDER BY created_at ASC")
    todos = result.to_a.map { |row| row_to_hash(row) }
    session.close
    todos
  end

  def find(id)
    session = DatabaseConfig.client.session
    result = session.call("SELECT * FROM todos WHERE id = $1", [id])
    row = result.to_a.first
    session.close
    row ? row_to_hash(row) : nil
  end

  def create(title:)
    session = DatabaseConfig.client.session
    result = session.call(
      "INSERT INTO todos (title, completed, created_at, updated_at) VALUES ($1, $2, NOW(), NOW()) RETURNING *",
      [title, false]
    )
    todo = row_to_hash(result.to_a.first)
    session.close
    todo
  end

  def update(id, attrs = {})
    updates = []
    params = []
    param_count = 1

    if attrs.key?(:title)
      updates << "title = $#{param_count}"
      params << attrs[:title]
      param_count += 1
    end

    if attrs.key?(:completed)
      updates << "completed = $#{param_count}"
      params << attrs[:completed]
      param_count += 1
    end

    updates << "updated_at = NOW()"
    params << id

    session = DatabaseConfig.client.session
    result = session.call(
      "UPDATE todos SET #{updates.join(", ")} WHERE id = $#{param_count} RETURNING *",
      params
    )
    row = result.to_a.first
    session.close
    row ? row_to_hash(row) : nil
  end

  def delete(id)
    session = DatabaseConfig.client.session
    result = session.call("DELETE FROM todos WHERE id = $1 RETURNING id", [id])
    deleted = !result.to_a.empty?
    session.close
    deleted
  end

  def clear_completed
    session = DatabaseConfig.client.session
    session.call("DELETE FROM todos WHERE completed = TRUE")
    session.close
    true
  end

  def toggle_all(completed)
    session = DatabaseConfig.client.session
    session.call("UPDATE todos SET completed = $1, updated_at = NOW()", [completed])
    session.close
    true
  end

  def active_count
    session = DatabaseConfig.client.session
    result = session.call("SELECT COUNT(*) FROM todos WHERE completed = FALSE")
    count = result.to_a.first.first
    session.close
    count
  end

  def completed_count
    session = DatabaseConfig.client.session
    result = session.call("SELECT COUNT(*) FROM todos WHERE completed = TRUE")
    count = result.to_a.first.first
    session.close
    count
  end

  private

  def row_to_hash(row)
    {
      id: row[0],
      title: row[1],
      completed: row[2],
      created_at: row[3]&.iso8601,
      updated_at: row[4]&.iso8601
    }
  end
end
