# frozen_string_literal: true

require "funapi"

# User registration
UserRegistrationSchema = FunApi::Schema.define do
  required(:user).hash do
    required(:username).filled(:string)
    required(:email).filled(:string)
    required(:password).filled(:string)
  end
end

# User login
UserLoginSchema = FunApi::Schema.define do
  required(:user).hash do
    required(:email).filled(:string)
    required(:password).filled(:string)
  end
end

# Update user
UserUpdateSchema = FunApi::Schema.define do
  required(:user).hash do
    optional(:email).filled(:string)
    optional(:username).filled(:string)
    optional(:password).filled(:string)
    optional(:bio).maybe(:string)
    optional(:image).maybe(:string)
  end
end
