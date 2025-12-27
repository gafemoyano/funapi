# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:favorites) do
      foreign_key :user_id, :users, null: false, on_delete: :cascade
      foreign_key :article_id, :articles, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      primary_key [:user_id, :article_id]
      index :user_id
      index :article_id
    end
  end
end
