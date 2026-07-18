# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestStreaming < Minitest::Test
  def drive(app, path, **options)
    env = Rack::MockRequest.env_for(path, **options)
    status, headers, body = Async { app.call(env) }.wait
    io = StringIO.new
    body.call(io)
    [status, headers, io.string]
  end

  def test_websocket_routes_excluded_from_openapi
    app = FunApi::App.new do |api|
      api.get("/hi") { |_input, _req| [{ok: true}, 200] }
      api.websocket("/ws") { |_socket, _input| }
    end

    res = nil
    Async { res = Rack::MockRequest.new(app).get("/openapi.json") }.wait
    paths = JSON.parse(res.body)["paths"].keys

    assert_includes paths, "/hi"
    refute_includes paths, "/ws"
  end

  def test_streaming_response_writes_chunks
    app = FunApi::App.new do |api|
      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
          3.times { |i| stream << "chunk #{i}\n" }
        end
      end
    end

    status, headers, body = drive(app, "/stream")

    assert_equal 200, status
    assert_equal "text/plain", headers["content-type"]
    assert_equal "chunk 0\nchunk 1\nchunk 2\n", body
  end

  def test_streaming_response_omits_content_length
    app = FunApi::App.new do |api|
      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new(headers: {"content-length" => "5"}) do |stream|
          stream.write("hello")
        end
      end
    end

    _status, headers, _body = drive(app, "/stream")
    refute headers.key?("content-length")
  end

  def test_streaming_custom_status_and_headers
    app = FunApi::App.new do |api|
      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new(status: 202, headers: {"x-trace" => "abc"}) do |stream|
          stream.write("ok")
        end
      end
    end

    status, headers, body = drive(app, "/stream")
    assert_equal 202, status
    assert_equal "abc", headers["x-trace"]
    assert_equal "ok", body
  end

  def test_streaming_swallows_client_disconnect
    app = FunApi::App.new do |api|
      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new do |stream|
          stream.write("first")
          raise Errno::EPIPE, "client gone"
        end
      end
    end

    status, _headers, body = drive(app, "/stream")
    assert_equal 200, status
    assert_equal "first", body
  end

  def test_streaming_reraises_non_disconnect_errors
    app = FunApi::App.new do |api|
      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new do |stream|
          stream.write("x")
          raise "boom"
        end
      end
    end

    assert_raises(RuntimeError) { drive(app, "/stream") }
  end

  def test_sse_formats_event_fields
    app = FunApi::App.new do |api|
      api.get "/events" do |_input, _req|
        FunApi::SSE.response do |sse|
          sse.send(data: {tick: 1}, event: "tick", id: "1")
        end
      end
    end

    status, headers, body = drive(app, "/events")

    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
    assert_equal "no-cache", headers["cache-control"]
    assert_equal "event: tick\nid: 1\ndata: {\"tick\":1}\n\n", body
  end

  def test_sse_splits_multiline_string_data
    app = FunApi::App.new do |api|
      api.get "/events" do |_input, _req|
        FunApi::SSE.response do |sse|
          sse.send(data: "line one\nline two")
        end
      end
    end

    _status, _headers, body = drive(app, "/events")
    assert_equal "data: line one\ndata: line two\n\n", body
  end

  def test_sse_comment_and_retry
    app = FunApi::App.new do |api|
      api.get "/events" do |_input, _req|
        FunApi::SSE.response do |sse|
          sse.comment("keepalive")
          sse.send(data: "bye", retry: 3000)
        end
      end
    end

    _status, _headers, body = drive(app, "/events")
    assert_equal ":keepalive\n\nretry: 3000\ndata: bye\n\n", body
  end

  def test_sse_string_data_not_json_encoded
    app = FunApi::App.new do |api|
      api.get "/events" do |_input, _req|
        FunApi::SSE.response do |sse|
          sse.send(data: "plain text")
        end
      end
    end

    _status, _headers, body = drive(app, "/events")
    assert_equal "data: plain text\n\n", body
  end
end
