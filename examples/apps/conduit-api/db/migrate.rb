# frozen_string_literal: true

require_relative "../config/database"

Sequel.extension :migration

puts "Running migrations..."
Sequel::Migrator.run(DB, File.join(__dir__, "migrations"))
puts "Migrations complete!"
