# frozen_string_literal: true

module FunApi
  class Config
    attr_accessor :bind, :port, :env, :workers, :tls, :rack_app

    def initialize(
      bind: 'https://localhost',   # Falcon defaults to HTTPS in dev
      port: 9292,
      env:  ENV.fetch('RACK_ENV', 'development'),
      workers: nil,                # let falcon default; can pass via --count
      tls: {}, # {cert:, key:} if you want to override
      rack_app: nil
    )
      @bind = bind
      @port = port
      @env = env
      @workers = workers
      @tls = tls
      @rack_app = rack_app
    end
  end
end
