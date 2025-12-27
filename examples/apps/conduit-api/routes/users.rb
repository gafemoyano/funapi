# frozen_string_literal: true

require_relative "../models/user"
require_relative "../schemas/user_schemas"
require_relative "../services/auth"

module Routes
  module Users
    def self.register(api)
      # Registration
      api.post "/api/users", body: UserRegistrationSchema do |input, _req, _task|
        user_params = input[:body][:user]

        begin
          user = User.create_with_password(
            email: user_params[:email],
            username: user_params[:username],
            password: user_params[:password]
          )

          [{ user: user.to_auth_json }, 201]
        rescue Sequel::ValidationFailed => e
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: { errors: { body: e.errors.full_messages } }
          )
        rescue Sequel::UniqueConstraintViolation
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: { errors: { body: ["Email or username already taken"] } }
          )
        end
      end

      # Login
      api.post "/api/users/login", body: UserLoginSchema do |input, _req, _task|
        user_params = input[:body][:user]

        user = User.find(email: user_params[:email])

        unless user&.authenticate(user_params[:password])
          raise FunApi::HTTPException.new(
            status_code: 401,
            detail: { errors: { body: ["Email or password is invalid"] } }
          )
        end

        [{ user: user.to_auth_json }, 200]
      end

      # Get current user
      api.get "/api/user" do |_input, req, _task|
        user_id = Auth.authenticate!(req)
        user = User[user_id]

        unless user
          raise FunApi::HTTPException.new(status_code: 404, detail: "User not found")
        end

        [{ user: user.to_auth_json }, 200]
      end

      # Update current user
      api.put "/api/user", body: UserUpdateSchema do |input, req, _task|
        user_id = Auth.authenticate!(req)
        user = User[user_id]

        unless user
          raise FunApi::HTTPException.new(status_code: 404, detail: "User not found")
        end

        user_params = input[:body][:user]
        attrs = {}

        attrs[:email] = user_params[:email] if user_params[:email]
        attrs[:username] = user_params[:username] if user_params[:username]
        attrs[:bio] = user_params[:bio] if user_params.key?(:bio)
        attrs[:image] = user_params[:image] if user_params.key?(:image)

        if user_params[:password]
          attrs[:password_hash] = Auth.hash_password(user_params[:password])
        end

        begin
          user.update(attrs)
          [{ user: user.to_auth_json }, 200]
        rescue Sequel::ValidationFailed => e
          raise FunApi::HTTPException.new(
            status_code: 422,
            detail: { errors: { body: e.errors.full_messages } }
          )
        end
      end
    end
  end
end
