# frozen_string_literal: true

require "sequel"
require_relative "database/sequel/fibered_connection_pool"

module FunApi
  module Sequel
    def self.connect(url, pool_class: ::Sequel::FiberedConnectionPool, **opts)
      ::Sequel.connect(url, pool_class: pool_class, **opts)
    end
  end
end
