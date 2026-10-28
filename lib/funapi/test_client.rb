# frozen_string_literal: true

require "json"
require "stringio"
require "rack"
require "async"
require "funapi"

module FunApi
  class TestClient
    class Response
      attr_reader :status, :headers, :body

      def initialize(status, headers, body)
        @status = status
        @headers = headers
        @body = body
      end

      def json
        JSON.parse(@body, symbolize_names: true)
      end

      def [](key)
        @headers[key.to_s.downcase]
      end

      def content_type
        self["content-type"]
      end

      def success?
        @status >= 200 && @status < 300
      end
    end

    class StreamResponse
      attr_reader :status, :headers, :chunks

      def initialize(status, headers, chunks)
        @status = status
        @headers = headers
        @chunks = chunks
      end

      def body
        @chunks.join
      end

      def [](key)
        @headers[key.to_s.downcase]
      end

      def events
        body.split("\n\n").filter_map do |block|
          event = {}
          data_lines = []
          block.each_line(chomp: true) do |line|
            next if line.empty? || line.start_with?(":")

            field, _, value = line.partition(":")
            value = value.delete_prefix(" ")
            case field
            when "event" then event[:event] = value
            when "id" then event[:id] = value
            when "retry" then event[:retry] = value.to_i
            when "data" then data_lines << value
            end
          end
          event[:data] = data_lines.join("\n") unless data_lines.empty?
          event.empty? ? nil : event
        end
      end
    end

    class Collector
      attr_reader :chunks

      def initialize
        @chunks = []
      end

      def write(data)
        chunk = data.to_s
        @chunks << chunk
        chunk.bytesize
      end

      def <<(data)
        write(data)
        self
      end

      def print(*args)
        args.each { |arg| write(arg) }
        nil
      end

      def flush
      end

      def close
      end
    end

    def initialize(app)
      @app = app
    end

    def get(path, params: {}, headers: {})
      request("GET", path, params: params, headers: headers)
    end

    def post(path, json: nil, body: nil, params: {}, headers: {})
      request("POST", path, json: json, body: body, params: params, headers: headers)
    end

    def put(path, json: nil, body: nil, params: {}, headers: {})
      request("PUT", path, json: json, body: body, params: params, headers: headers)
    end

    def patch(path, json: nil, body: nil, params: {}, headers: {})
      request("PATCH", path, json: json, body: body, params: params, headers: headers)
    end

    def delete(path, json: nil, body: nil, params: {}, headers: {})
      request("DELETE", path, json: json, body: body, params: params, headers: headers)
    end

    def request(method, path, json: nil, body: nil, params: {}, headers: {})
      env = build_env(method, path, json: json, body: body, params: params, headers: headers)
      status, response_headers, chunks = perform(env)
      Response.new(status, response_headers, chunks.join)
    end

    def stream(path, method: "GET", params: {}, headers: {}, json: nil)
      env = build_env(method, path, json: json, body: nil, params: params, headers: headers)
      status, response_headers, chunks = perform(env)
      StreamResponse.new(status, response_headers, chunks)
    end
    alias_method :sse, :stream

    private

    def perform(env)
      run_async do
        status, headers, body = @app.call(env)
        [status, normalize_headers(headers), collect_chunks(body)]
      end
    end

    def run_async(&block)
      if Async::Task.current?
        block.call
      else
        Async { block.call }.wait
      end
    end

    def collect_chunks(body)
      if body.respond_to?(:each)
        chunks = []
        body.each { |chunk| chunks << chunk }
        chunks
      elsif body.respond_to?(:call)
        collector = Collector.new
        body.call(collector)
        collector.chunks
      else
        [body.to_s]
      end
    ensure
      body.close if body.respond_to?(:close)
    end

    def build_env(method, path, json:, body:, params:, headers:)
      verb = method.to_s.upcase
      full_path = append_params(path, params)

      options = {method: verb}

      if json
        options[:input] = JSON.dump(json)
        options["CONTENT_TYPE"] = "application/json"
      elsif body
        options[:input] = body
      end

      headers.each do |name, value|
        options[header_env_key(name)] = value.to_s
      end

      Rack::MockRequest.env_for(full_path, **options)
    end

    def append_params(path, params)
      return path if params.nil? || params.empty?

      query = Rack::Utils.build_nested_query(stringify(params))
      separator = path.include?("?") ? "&" : "?"
      "#{path}#{separator}#{query}"
    end

    def stringify(params)
      params.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value
      end
    end

    def header_env_key(name)
      key = name.to_s.upcase.tr("-", "_")
      if %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
        key
      else
        "HTTP_#{key}"
      end
    end

    def normalize_headers(headers)
      headers.each_with_object({}) do |(key, value), acc|
        acc[key.to_s.downcase] = value.is_a?(Array) ? value.join("\n") : value
      end
    end
  end
end
