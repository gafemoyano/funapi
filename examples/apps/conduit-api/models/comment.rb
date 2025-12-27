# frozen_string_literal: true

require "sequel"

class Comment < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  many_to_one :article
  many_to_one :author, class: :User, key: :author_id

  def validate
    super
    validates_presence [:body, :article_id, :author_id]
  end

  def to_json_api(current_user_id: nil)
    {
      id: id,
      createdAt: created_at.iso8601,
      updatedAt: updated_at.iso8601,
      body: body,
      author: author.to_profile_json(current_user_id: current_user_id)
    }
  end
end
