# frozen_string_literal: true

require "sequel"
require_relative "../services/auth"

class User < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  one_to_many :articles, key: :author_id
  one_to_many :comments, key: :author_id
  many_to_many :favorited_articles,
    left_key: :user_id,
    right_key: :article_id,
    join_table: :favorites,
    class: :Article

  def validate
    super
    validates_presence [:email, :username, :password_hash]
    validates_unique :email
    validates_unique :username
    validates_format(/\A[^@\s]+@[^@\s]+\z/, :email, message: "is not a valid email")
    validates_min_length 3, :username
  end

  def self.create_with_password(email:, username:, password:)
    password_hash = Auth.hash_password(password)
    create(
      email: email,
      username: username,
      password_hash: password_hash
    )
  end

  def authenticate(password)
    Auth.verify_password(password, password_hash)
  end

  def generate_auth_token
    Auth.generate_token(id)
  end

  def to_auth_json
    {
      email: email,
      token: generate_auth_token,
      username: username,
      bio: bio,
      image: image
    }
  end

  def to_profile_json(current_user_id: nil)
    {
      username: username,
      bio: bio,
      image: image,
      following: current_user_id ? following?(current_user_id) : false
    }
  end

  def following?(follower_id)
    DB[:follows].where(follower_id: follower_id, followee_id: id).count > 0
  end

  def follow!(follower_id)
    DB[:follows].insert_conflict.insert(follower_id: follower_id, followee_id: id)
  end

  def unfollow!(follower_id)
    DB[:follows].where(follower_id: follower_id, followee_id: id).delete
  end
end
