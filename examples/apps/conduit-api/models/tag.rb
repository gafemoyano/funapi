# frozen_string_literal: true

require "sequel"

class Tag < Sequel::Model
  plugin :validation_helpers

  many_to_many :articles, left_key: :tag_id, right_key: :article_id, join_table: :article_tags

  def validate
    super
    validates_presence :name
    validates_unique :name
  end

  def self.find_or_create(name:)
    find(name: name) || create(name: name)
  end
end
