# frozen_string_literal: true

require "json"
require_relative "streaming_response"

module FunApi
  module SSE
    def self.response(status: 200, heartbeat: nil, headers: {}, &block)
      raise ArgumentError, "SSE.response requires a block" unless block

      sse_headers = {
        "cache-control" => "no-cache",
        "connection" => "keep-alive"
      }.merge(headers)

      StreamingResponse.new(
        content_type: "text/event-stream",
        status: status,
        headers: sse_headers
      ) do |stream|
        writer = Writer.new(stream)
        heartbeat_task = start_heartbeat(writer, heartbeat)
        begin
          block.call(writer)
        ensure
          heartbeat_task&.stop
        end
      end
    end

    def self.start_heartbeat(writer, interval)
      return nil unless interval

      parent = Async::Task.current?
      return nil unless parent

      parent.async do
        loop do
          ::Kernel.sleep(interval)
          writer.comment("heartbeat")
        end
      end
    end

    class Writer
      def initialize(stream)
        @stream = stream
      end

      def send(data: nil, event: nil, id: nil, retry: nil)
        retry_ms = binding.local_variable_get(:retry)
        parts = []
        parts << "event: #{event}" if event
        parts << "id: #{id}" if id
        parts << "retry: #{retry_ms}" if retry_ms
        parts.concat(data_lines(data)) unless data.nil?

        write("#{parts.join("\n")}\n\n")
      end

      def comment(text = "")
        write(":#{text}\n\n")
      end

      def close
        @stream.close
      rescue
        nil
      end

      private

      def data_lines(data)
        payload = data.is_a?(String) ? data : JSON.generate(data)
        payload.split("\n", -1).map { |line| "data: #{line}" }
      end

      def write(chunk)
        @stream.write(chunk)
        @stream.flush if @stream.respond_to?(:flush)
        chunk
      end
    end
  end
end
