# frozen_string_literal: true

require_relative 'fun_api/version'
require_relative 'fun_api/application'

module FunApi
  class Error < StandardError; end

  def self.build_app(&block)
    # Return a Rack app from your App DSL:
    app = FunApi::App.new(&block)
    builder = Rack::Builder.new { run app }
    [app, builder.to_app]
  end

  def self.run!(boot_path:, constant:, port: 3000, bind: 'https://localhost', env: 'development', workers: nil, tls: {})
    cfg = Config.new(
      bind: bind, port: port, env: env, workers: workers, tls: tls,
      rack_app: { boot_path: boot_path, constant: constant }
    )
    Server::Falcon.new(cfg).start
  end
end
