# frozen_string_literal: true

require "sequel"

# Connect to SQLite database
DB = Sequel.connect("sqlite://todo.db")

# Create todos table if it doesn't exist
DB.create_table? :todos do
  primary_key :id
  String :title, null: false
  TrueClass :completed, default: false
  DateTime :created_at
  DateTime :updated_at
end

# Sequel model
class Todo < Sequel::Model
  plugin :timestamps, update_on_create: true

  def validate
    super
    errors.add(:title, "cannot be empty") if !title || title.strip.empty?
  end

  def to_hash
    {
      id: id,
      title: title,
      completed: completed,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end

# Helper methods for async-safe database operations
module TodoRepository
  extend self

  def all
    Todo.order(:created_at).all
  end

  def active
    Todo.where(completed: false).order(:created_at).all
  end

  def completed
    Todo.where(completed: true).order(:created_at).all
  end

  def find(id)
    Todo[id]
  end

  def create(title:)
    Todo.create(title: title.strip, completed: false)
  end

  def update(id, attrs)
    todo = find(id)
    return nil unless todo

    todo.update(attrs)
    todo
  end

  def delete(id)
    todo = find(id)
    return false unless todo

    todo.delete
    true
  end

  def clear_completed
    Todo.where(completed: true).delete
  end

  def toggle_all(completed)
    Todo.update(completed: completed)
  end

  def active_count
    Todo.where(completed: false).count
  end

  def completed_count
    Todo.where(completed: true).count
  end
end
