# frozen_string_literal: true

require_relative "../models/user"
require_relative "../services/auth"

module Routes
  module Profiles
    def self.register(api)
      # Get profile
      api.get "/api/profiles/:username" do |input, req, _task|
        username = input[:path]["username"]
        current_user_id = Auth.current_user_id(req)

        user = User.find(username: username)

        unless user
          raise FunApi::HTTPException.new(status_code: 404, detail: "Profile not found")
        end

        [{ profile: user.to_profile_json(current_user_id: current_user_id) }, 200]
      end

      # Follow user
      api.post "/api/profiles/:username/follow" do |input, req, _task|
        username = input[:path]["username"]
        current_user_id = Auth.authenticate!(req)

        user = User.find(username: username)

        unless user
          raise FunApi::HTTPException.new(status_code: 404, detail: "Profile not found")
        end

        if user.id == current_user_id
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: "Cannot follow yourself"
          )
        end

        user.follow!(current_user_id)

        [{ profile: user.to_profile_json(current_user_id: current_user_id) }, 200]
      end

      # Unfollow user
      api.delete "/api/profiles/:username/follow" do |input, req, _task|
        username = input[:path]["username"]
        current_user_id = Auth.authenticate!(req)

        user = User.find(username: username)

        unless user
          raise FunApi::HTTPException.new(status_code: 404, detail: "Profile not found")
        end

        user.unfollow!(current_user_id)

        [{ profile: user.to_profile_json(current_user_id: current_user_id) }, 200]
      end
    end
  end
end
