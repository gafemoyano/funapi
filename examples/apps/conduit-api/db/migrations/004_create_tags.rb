# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:tags) do
      primary_key :id
      String :name, null: false, unique: true

      index :name, unique: true
    end

    create_table(:article_tags) do
      foreign_key :article_id, :articles, null: false, on_delete: :cascade
      foreign_key :tag_id, :tags, null: false, on_delete: :cascade

      primary_key [:article_id, :tag_id]
      index :article_id
      index :tag_id
    end
  end
end
