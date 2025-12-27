# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id
      String :email, null: false, unique: true
      String :username, null: false, unique: true
      String :password_hash, null: false
      String :bio, text: true
      String :image
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :email, unique: true
      index :username, unique: true
    end
  end
end
