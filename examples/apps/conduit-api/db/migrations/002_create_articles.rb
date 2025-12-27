# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:articles) do
      primary_key :id
      String :slug, null: false, unique: true
      String :title, null: false
      String :description, null: false
      String :body, text: true, null: false
      foreign_key :author_id, :users, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :author_id
      index :created_at
    end
  end
end
