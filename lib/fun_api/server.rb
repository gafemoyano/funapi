# frozen_string_literal: true

require 'open3'

module FalconAPI
  # Generic server adapter interface
  class Server
    def initialize(config) = @config = config
    def start = raise(NotImplementedError)
  end
end
