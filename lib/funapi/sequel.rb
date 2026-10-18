# frozen_string_literal: true

require "sequel"

::Sequel.extension :fiber_concurrency

module FunApi
  module Sequel
    def self.connect(url, pool_class: :timed_queue, **opts)
      ::Sequel.connect(url, pool_class: pool_class, **opts)
    end
  end
end
