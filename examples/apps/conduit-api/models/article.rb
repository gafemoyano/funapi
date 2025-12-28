# frozen_string_literal: true

require "sequel"

class Article < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  many_to_one :author, class: :User, key: :author_id
  one_to_many :comments
  many_to_many :tags, left_key: :article_id, right_key: :tag_id, join_table: :article_tags
  many_to_many :favorited_by,
    left_key: :article_id,
    right_key: :user_id,
    join_table: :favorites,
    class: :User

  def validate
    super
    validates_presence [:slug, :title, :description, :body, :author_id]
    validates_unique :slug
  end

  def self.create_with_slug(title:, description:, body:, author_id:, tag_list: [])
    slug = generate_slug(title)
    article = create(
      slug: slug,
      title: title,
      description: description,
      body: body,
      author_id: author_id
    )

    # Add tags
    tag_list.each do |tag_name|
      tag = Tag.find_or_create(name: tag_name)
      article.add_tag(tag)
    end

    article
  end

  def update_with_tags(attrs, tag_list: nil)
    # Update slug if title changes
    if attrs[:title] && attrs[:title] != title
      attrs[:slug] = self.class.generate_slug(attrs[:title])
    end

    update(attrs)

    # Update tags if provided
    if tag_list
      remove_all_tags
      tag_list.each do |tag_name|
        tag = Tag.find_or_create(name: tag_name)
        add_tag(tag)
      end
    end

    self
  end

  def self.generate_slug(title)
    base_slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/(^-|-$)/, "")
    slug = base_slug
    counter = 1

    while Article.where(slug: slug).count > 0
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug
  end

  def favorited_by?(user_id)
    DB[:favorites].where(user_id: user_id, article_id: id).count > 0
  end

  def favorites_count
    DB[:favorites].where(article_id: id).count
  end

  def to_json_api(current_user_id: nil)
    {
      slug: slug,
      title: title,
      description: description,
      body: body,
      tagList: tags.map(&:name),
      createdAt: created_at.iso8601,
      updatedAt: updated_at.iso8601,
      favorited: current_user_id ? favorited_by?(current_user_id) : false,
      favoritesCount: favorites_count,
      author: author.to_profile_json(current_user_id: current_user_id)
    }
  end
end
