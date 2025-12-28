# frozen_string_literal: true

require "sequel"

# Database connection
DB = Sequel.connect(
  adapter: "postgres",
  host: ENV.fetch("POSTGRES_HOST", "localhost"),
  port: ENV.fetch("POSTGRES_PORT", "5432").to_i,
  database: ENV.fetch("POSTGRES_DB", "conduit"),
  user: ENV.fetch("POSTGRES_USER", "postgres"),
  password: ENV.fetch("POSTGRES_PASSWORD", "postgres"),
  max_connections: 10
)

# Enable extension for UUID support (optional)
DB.extension :pg_array, :pg_json

puts "Database connected: #{DB.opts[:database]}@#{DB.opts[:host]}"
