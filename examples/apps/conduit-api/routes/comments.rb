# frozen_string_literal: true

require_relative "../models/comment"
require_relative "../models/article"
require_relative "../schemas/comment_schemas"
require_relative "../services/auth"

module Routes
  module Comments
    def self.register(api)
      # Get comments for article
      api.get "/api/articles/:slug/comments" do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.current_user_id(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        comments = article.comments_dataset
          .order(Sequel.desc(:created_at))
          .all
          .map { |comment| comment.to_json_api(current_user_id: current_user_id) }

        [{ comments: comments }, 200]
      end

      # Create comment
      api.post "/api/articles/:slug/comments", body: CommentCreateSchema do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.authenticate!(req)
        comment_params = input[:body][:comment]

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        begin
          comment = Comment.create(
            body: comment_params[:body],
            article_id: article.id,
            author_id: current_user_id
          )

          [{ comment: comment.to_json_api(current_user_id: current_user_id) }, 201]
        rescue Sequel::ValidationFailed => e
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: { errors: { body: e.errors.full_messages } }
          )
        end
      end

      # Delete comment
      api.delete "/api/articles/:slug/comments/:id" do |input, req, _task|
        slug = input[:path]["slug"]
        comment_id = input[:path]["id"].to_i
        current_user_id = Auth.authenticate!(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        comment = Comment[comment_id]

        unless comment
          raise FunApi::HTTPException.new(status_code: 404, detail: "Comment not found")
        end

        unless comment.author_id == current_user_id
          raise FunApi::HTTPException.new(status_code: 403, detail: "Forbidden")
        end

        comment.destroy

        [{ message: "Comment deleted" }, 200]
      end
    end
  end
end
