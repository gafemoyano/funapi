# frozen_string_literal: true

require_relative 'fun_api/version'
require_relative 'fun_api/exceptions'
require_relative 'fun_api/schema'
require_relative 'fun_api/depends'
require_relative 'fun_api/dependency_wrapper'
require_relative 'fun_api/async'
require_relative 'fun_api/router'
require_relative 'fun_api/application'

module FunApi
  class Error < StandardError; end
end
