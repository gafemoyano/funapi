# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:comments) do
      primary_key :id
      String :body, text: true, null: false
      foreign_key :article_id, :articles, null: false, on_delete: :cascade
      foreign_key :author_id, :users, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :article_id
      index :author_id
      index :created_at
    end
  end
end
