# frozen_string_literal: true

require "test_helper"
require "socket"

begin
  require "async/http/server"
  require "async/http/endpoint"
  require "async/http/client"
  require "async/websocket/client"
  require "protocol/rack"
  require "funapi/websocket"
  SERVER_STACK_AVAILABLE = true
rescue LoadError
  SERVER_STACK_AVAILABLE = false
end

# End-to-end streaming/SSE/WebSocket over a real Falcon-compatible async-http
# server booted on an ephemeral port. This is where actual streaming (as opposed
# to the eager StringIO fallback used in test_streaming.rb) is exercised.
class TestStreamingIntegration < Minitest::Test
  HTTP11 = SERVER_STACK_AVAILABLE ? Async::HTTP::Protocol::HTTP11 : nil

  def setup
    skip "async-http server stack not available" unless SERVER_STACK_AVAILABLE
  end

  def free_port
    server = TCPServer.new("localhost", 0)
    port = server.addr[1]
    server.close
    port
  end

  def with_server(app)
    port = free_port
    Async do |task|
      endpoint = Async::HTTP::Endpoint.parse("http://localhost:#{port}").with(protocol: HTTP11)
      server = Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), endpoint)
      server_task = task.async { server.run }

      wait_until_ready(port)
      begin
        yield port, endpoint
      ensure
        server_task.stop
      end
    end.wait
  end

  def wait_until_ready(port)
    20.times do
      TCPSocket.new("localhost", port).close
      return
    rescue Errno::ECONNREFUSED
      Async::Task.current.sleep(0.01)
    end
    raise "server did not become ready on port #{port}"
  end

  def test_streaming_delivers_chunks_incrementally
    events = []
    app = FunApi::App.new do |api|
      api.register(:resource) do
        events << :acquired
        [:resource, -> { events << :released }]
      end
      api.get "/stream", depends: [:resource] do |_input, _req, _task, resource:, background:|
        background.add_task(-> { events << :background })
        FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
          events << :body_start
          3.times do |i|
            FunApi.sleep(0.03)
            assert_equal :resource, resource
            assert_equal %i[acquired body_start], events
            stream.write("chunk#{i}\n")
          end
          events << :body_end
        end
      end
    end

    with_server(app) do |_port, endpoint|
      client = Async::HTTP::Client.new(endpoint)
      begin
        response = client.get("/stream")
        chunks = []
        response.body.each { |chunk| chunks << chunk }
        Async::Task.current.with_timeout(2) do
          sleep 0.001 until events.include?(:released)
        end
        assert_equal "chunk0\nchunk1\nchunk2\n", chunks.join
        assert_operator chunks.length, :>=, 2, "expected multiple streamed chunks"
        assert_equal %i[acquired body_start body_end background released], events
      ensure
        client.close
      end
    end
  end

  def test_disconnected_client_finalizes_slow_stream
    events = []
    app = FunApi::App.new do |api|
      api.register(:resource) do
        events << :acquired
        [:resource, -> {
          sleep 0.001
          events << :released
        }]
      end
      api.get "/stream", depends: [:resource] do |_input, _req, _task, resource:, background:|
        background.add_task(-> {
          sleep 0.001
          events << :background
        })
        FunApi::StreamingResponse.new do |stream|
          events << :body_start
          100.times do
            stream.write(resource.to_s * 8192)
            sleep 0.01
          end
          events << :all_chunks_written
        ensure
          events << :body_end
        end
      end
    end

    with_server(app) do |port, _endpoint|
      socket = TCPSocket.new("localhost", port)
      socket.write("GET /stream HTTP/1.1\r\nHost: localhost\r\n\r\n")
      assert_includes socket.readpartial(4096), "200"
      assert_equal %i[acquired body_start], events
      socket.close
      Async::Task.current.with_timeout(3) do
        sleep 0.01 until events.include?(:released)
      end
      assert_equal %i[acquired body_start body_end background released], events
    ensure
      socket&.close unless socket&.closed?
    end
  end

  def test_stream_error_finalizes_after_last_chunk
    events = []
    app = FunApi::App.new do |api|
      api.register(:resource) { [:resource, -> { events << :released }] }
      api.get "/stream", depends: [:resource] do |_input, _req, _task, resource:, background:|
        background.add_task(-> { events << :background })
        FunApi::StreamingResponse.new do |stream|
          stream.write(resource.to_s)
          sleep 0.03
          events << :body_error
          raise "stream failed"
        end
      end
    end

    with_server(app) do |_port, endpoint|
      client = Async::HTTP::Client.new(endpoint)
      begin
        Async::Task.current.with_timeout(2) do
          response = client.get("/stream")
          assert_equal "resource", response.body.read
          assert_empty events
          response.body.each { |_chunk| }
          sleep 0.001 until events.include?(:released)
        end
        assert_equal %i[body_error background released], events
      ensure
        client.close
      end
    end
  end

  def test_sse_emits_heartbeats_and_events
    app = FunApi::App.new do |api|
      api.get "/events" do |_input, _req|
        FunApi::SSE.response(heartbeat: 0.03) do |sse|
          FunApi.sleep(0.12)
          sse.send(data: {done: true}, event: "done")
        end
      end
    end

    with_server(app) do |_port, endpoint|
      client = Async::HTTP::Client.new(endpoint)
      begin
        response = client.get("/events")
        raw = +""
        response.body.each { |chunk| raw << chunk }
        assert_operator raw.scan(":heartbeat").length, :>=, 2, "expected heartbeat pings"
        assert_includes raw, "event: done"
        assert_includes raw, "data: {\"done\":true}"
      ensure
        client.close
      end
    end
  end

  def test_websocket_echo_and_path_params
    app = FunApi::App.new do |api|
      api.websocket "/ws/:room" do |socket, input|
        socket.write("room=#{input[:path][:room]}")
        while (message = socket.read)
          socket.write("echo: #{message.to_str}")
        end
      end
    end

    with_server(app) do |port, _endpoint|
      ws_endpoint = Async::HTTP::Endpoint
        .parse("http://localhost:#{port}/ws/lobby")
        .with(protocol: HTTP11)

      Async::WebSocket::Client.connect(ws_endpoint) do |connection|
        assert_equal "room=lobby", connection.read.to_str
        connection.write("hello")
        assert_equal "echo: hello", connection.read.to_str
      end
    end
  end

  def test_non_upgrade_request_gets_426
    app = FunApi::App.new do |api|
      api.websocket "/ws/:room" do |socket, _input|
        socket.write("hi")
      end
    end

    with_server(app) do |_port, endpoint|
      client = Async::HTTP::Client.new(endpoint)
      begin
        response = client.get("/ws/lobby")
        assert_equal 426, response.status
        response.body&.read
      ensure
        client.close
      end
    end
  end
end
