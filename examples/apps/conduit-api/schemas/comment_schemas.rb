# frozen_string_literal: true

require "funapi"

# Create comment
CommentCreateSchema = FunApi::Schema.define do
  required(:comment).hash do
    required(:body).filled(:string)
  end
end
