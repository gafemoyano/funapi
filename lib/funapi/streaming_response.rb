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

    class CompletionBody
      def initialize(body, &completion)
        @body = body
        @completion = completion
        @closed = false
        @consuming = false

        %i[each call to_ary].each do |method|
          next unless body.respond_to?(method)

          define_singleton_method(method) do |*args, &block|
            return enum_for(:each) if method == :each && !block
            return if @closed

            @consuming = true
            begin
              @body.public_send(method, *args, &block)
            ensure
              @consuming = false
              close
            end
          end
        end

        if body.respond_to?(:to_path)
          define_singleton_method(:to_path) { @body.to_path }
        end
      end

      def close
        return if @closing

        @closing = true
        begin
          unless @closed
            @closed = true
            @body.close if @body.respond_to?(:close)
          end
        ensure
          @closing = false
          unless @consuming
            completion, @completion = @completion, nil
            completion&.call
          end
        end
      end
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
