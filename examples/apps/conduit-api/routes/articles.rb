# frozen_string_literal: true

require_relative "../models/article"
require_relative "../models/user"
require_relative "../models/tag"
require_relative "../schemas/article_schemas"
require_relative "../services/auth"

module Routes
  module Articles
    def self.register(api)
      # List articles
      api.get "/api/articles", query: ArticleListQuerySchema do |input, req, _task|
        current_user_id = Auth.current_user_id(req)
        query_params = input[:query]

        dataset = Article.dataset
          .order(Sequel.desc(:created_at))

        # Filter by tag
        if query_params[:tag]
          tag = Tag.find(name: query_params[:tag])
          dataset = if tag
            dataset.where(id: tag.articles_dataset.select(:id))
          else
            dataset.where(Sequel.lit("1=0")) # No results
          end
        end

        # Filter by author
        if query_params[:author]
          author = User.find(username: query_params[:author])
          dataset = if author
            dataset.where(author_id: author.id)
          else
            dataset.where(Sequel.lit("1=0")) # No results
          end
        end

        # Filter by favorited
        if query_params[:favorited]
          user = User.find(username: query_params[:favorited])
          dataset = if user
            dataset.where(id: user.favorited_articles_dataset.select(:id))
          else
            dataset.where(Sequel.lit("1=0")) # No results
          end
        end

        # Pagination
        limit = query_params[:limit] || 20
        offset = query_params[:offset] || 0
        dataset = dataset.limit(limit).offset(offset)

        articles = dataset.all.map { |article| article.to_json_api(current_user_id: current_user_id) }
        articles_count = dataset.count

        [{articles: articles, articlesCount: articles_count}, 200]
      end

      # Get article feed (requires auth)
      api.get "/api/articles/feed" do |_input, req, _task|
        current_user_id = Auth.authenticate!(req)

        # Get articles from followed users
        followed_user_ids = DB[:follows]
          .where(follower_id: current_user_id)
          .select(:followee_id)

        articles = Article
          .where(author_id: followed_user_ids)
          .order(Sequel.desc(:created_at))
          .limit(20)
          .all
          .map { |article| article.to_json_api(current_user_id: current_user_id) }

        [{articles: articles, articlesCount: articles.length}, 200]
      end

      # Get single article
      api.get "/api/articles/:slug" do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.current_user_id(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        [{article: article.to_json_api(current_user_id: current_user_id)}, 200]
      end

      # Create article
      api.post "/api/articles", body: ArticleCreateSchema do |input, req, _task|
        current_user_id = Auth.authenticate!(req)
        article_params = input[:body][:article]

        begin
          article = Article.create_with_slug(
            title: article_params[:title],
            description: article_params[:description],
            body: article_params[:body],
            author_id: current_user_id,
            tag_list: article_params[:tagList] || []
          )

          [{article: article.to_json_api(current_user_id: current_user_id)}, 201]
        rescue Sequel::ValidationFailed => e
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: {errors: {body: e.errors.full_messages}}
          )
        end
      end

      # Update article
      api.put "/api/articles/:slug", body: ArticleUpdateSchema do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.authenticate!(req)
        article_params = input[:body][:article]

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        unless article.author_id == current_user_id
          raise FunApi::HTTPException.new(status_code: 403, detail: "Forbidden")
        end

        attrs = {}
        attrs[:title] = article_params[:title] if article_params[:title]
        attrs[:description] = article_params[:description] if article_params[:description]
        attrs[:body] = article_params[:body] if article_params[:body]

        begin
          article.update_with_tags(attrs, tag_list: article_params[:tagList])
          [{article: article.to_json_api(current_user_id: current_user_id)}, 200]
        rescue Sequel::ValidationFailed => e
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: {errors: {body: e.errors.full_messages}}
          )
        end
      end

      # Delete article
      api.delete "/api/articles/:slug" do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.authenticate!(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        unless article.author_id == current_user_id
          raise FunApi::HTTPException.new(status_code: 403, detail: "Forbidden")
        end

        article.destroy

        [{message: "Article deleted"}, 200]
      end

      # Favorite article
      api.post "/api/articles/:slug/favorite" do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.authenticate!(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        # Add favorite (ignore if already favorited)
        DB[:favorites].insert_conflict.insert(user_id: current_user_id, article_id: article.id)

        [{article: article.to_json_api(current_user_id: current_user_id)}, 200]
      end

      # Unfavorite article
      api.delete "/api/articles/:slug/favorite" do |input, req, _task|
        slug = input[:path]["slug"]
        current_user_id = Auth.authenticate!(req)

        article = Article.find(slug: slug)

        unless article
          raise FunApi::HTTPException.new(status_code: 404, detail: "Article not found")
        end

        DB[:favorites].where(user_id: current_user_id, article_id: article.id).delete

        [{article: article.to_json_api(current_user_id: current_user_id)}, 200]
      end
    end
  end
end
