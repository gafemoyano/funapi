# frozen_string_literal: true

require "async/websocket/adapters/rack"

module FunApi
  module WebSocket
    UPGRADE_REQUIRED = [
      426,
      {"content-type" => "text/plain", "connection" => "upgrade", "upgrade" => "websocket"},
      ["Upgrade Required"]
    ].freeze

    def self.open(env, &block)
      Async::WebSocket::Adapters::Rack.open(env, &block)
    end

    def self.upgrade_required
      status, headers, body = UPGRADE_REQUIRED
      [status, headers.dup, body.dup]
    end
  end
end
