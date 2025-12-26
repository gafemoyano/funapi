# frozen_string_literal: true

require_relative "funapi/version"
require_relative "funapi/exceptions"
require_relative "funapi/schema"
require_relative "funapi/depends"
require_relative "funapi/dependency_wrapper"
require_relative "funapi/async"
require_relative "funapi/router"
require_relative "funapi/application"

module FunApi
  class Error < StandardError; end
end
