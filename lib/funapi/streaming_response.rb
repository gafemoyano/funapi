# frozen_string_literal: true

module FunApi
  class StreamingResponse
    def initialize(content_type: "application/octet-stream", status: 200, headers: {}, &block)
      raise ArgumentError, "StreamingResponse requires a block" unless block

      @content_type = content_type
      @status = status
      @headers = headers
      @block = block
    end

    def to_response
      headers = {"content-type" => @content_type}.merge(@headers)
      headers.delete("content-length")
      [@status, headers, Body.new(@block)]
    end

    class Body
      def initialize(block)
        @block = block
      end

      def call(stream)
        @block.call(stream)
      rescue => error
        raise unless Body.disconnect?(error)
      ensure
        begin
          stream.close
        rescue
          nil
        end
      end

      def close
      end

      def self.disconnect?(error)
        return true if defined?(Protocol::HTTP::Body::Writable::Closed) &&
          error.is_a?(Protocol::HTTP::Body::Writable::Closed)

        case error
        when Errno::EPIPE, Errno::ECONNRESET, IOError
          true
        else
          false
        end
      end
    end
  end
end
