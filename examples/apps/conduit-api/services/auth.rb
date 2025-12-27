# frozen_string_literal: true

require "jwt"
require "bcrypt"

module Auth
  SECRET_KEY = ENV.fetch("JWT_SECRET", "your-secret-key-change-in-production")
  ALGORITHM = "HS256"

  module_function

  def hash_password(password)
    BCrypt::Password.create(password)
  end

  def verify_password(password, password_hash)
    BCrypt::Password.new(password_hash) == password
  end

  def generate_token(user_id)
    payload = {
      user_id: user_id,
      exp: Time.now.to_i + (24 * 60 * 60) # 24 hours
    }
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  def decode_token(token)
    decoded = JWT.decode(token, SECRET_KEY, true, {algorithm: ALGORITHM})
    decoded[0]["user_id"]
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end

  def extract_token_from_header(authorization_header)
    return nil unless authorization_header

    # Format: "Token jwt.token.here"
    parts = authorization_header.split(" ")
    return nil unless parts.length == 2 && parts[0] == "Token"

    parts[1]
  end

  def current_user_id(request)
    auth_header = request.get_header("HTTP_AUTHORIZATION")
    token = extract_token_from_header(auth_header)
    return nil unless token

    decode_token(token)
  end

  def authenticate!(request)
    user_id = current_user_id(request)
    raise FunApi::HTTPException.new(status_code: 401, detail: "Unauthorized") unless user_id

    user_id
  end
end
