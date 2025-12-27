# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:follows) do
      foreign_key :follower_id, :users, null: false, on_delete: :cascade
      foreign_key :followee_id, :users, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      primary_key [:follower_id, :followee_id]
      index :follower_id
      index :followee_id
    end
  end
end
