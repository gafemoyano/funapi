# frozen_string_literal: true

require "funapi"

# Create article
ArticleCreateSchema = FunApi::Schema.define do
  required(:article).hash do
    required(:title).filled(:string)
    required(:description).filled(:string)
    required(:body).filled(:string)
    optional(:tagList).array(:string)
  end
end

# Update article
ArticleUpdateSchema = FunApi::Schema.define do
  required(:article).hash do
    optional(:title).filled(:string)
    optional(:description).filled(:string)
    optional(:body).filled(:string)
    optional(:tagList).array(:string)
  end
end

# Article list query params
ArticleListQuerySchema = FunApi::Schema.define do
  optional(:tag).filled(:string)
  optional(:author).filled(:string)
  optional(:favorited).filled(:string)
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end
