# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestStreaming < Minitest::Test
  def managed_stream(events, &producer)
    FunApi::App.new do |api|
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
          producer.call(stream, resource)
        ensure
          events << :body_end
        end
      end
    end
  end

  def test_stream_completion_errors_and_disconnect_finalize_once
    [nil, RuntimeError, Errno::EPIPE, Errno::ECONNRESET, IOError].each do |error|
      events = []
      app = managed_stream(events) do |stream, resource|
        assert_equal :resource, resource
        sleep 0.01
        assert_equal %i[acquired body_start], events
        stream.write("chunk")
        raise error, "failure" if error
      end

      Async do
        body = app.call(Rack::MockRequest.env_for("/stream"))[2]
        sleep 0.01
        assert_equal [:acquired], events
        stream = StringIO.new
        if error == RuntimeError
          assert_raises(RuntimeError) { body.call(stream) }
        else
          body.call(stream)
        end
        assert stream.closed?
        body.close
        body.close
      end.wait

      assert_equal %i[acquired body_start body_end background released], events
    end
  end

  def test_unconsumed_close_outside_original_reactor
    events = []
    app = managed_stream(events) { flunk "unconsumed body must not run" }
    body = Async { app.call(Rack::MockRequest.env_for("/stream"))[2] }.wait
    assert_equal [:acquired], events
    body.close
    body.close
    assert_equal %i[acquired background released], events
  end

  def test_cancelled_stream_finishes_background_and_yielding_cleanup
    events = []
    app = managed_stream(events) { sleep 10 }
    app.on_shutdown do
      assert_equal %i[acquired body_start body_end background released], events
      events << :shutdown
    end
    Async do |task|
      body = app.call(Rack::MockRequest.env_for("/stream"))[2]
      consumer = task.async { body.call(StringIO.new) }
      assert_equal %i[acquired body_start], events
      consumer.stop
      body.close
      app.run_shutdown_hooks
    end.wait
    assert_equal %i[acquired body_start body_end background released shutdown], events
  end

  def test_shutdown_without_hooks_drains_failed_background_and_cleanup
    events = []
    app = FunApi::App.new do |api|
      api.register(:resource) do
        [:resource, -> {
          sleep 0.01
          events << :cleanup
          raise "cleanup failed"
        }]
      end
      api.get "/stream", depends: [:resource] do |_input, _req, _task, resource:, background:|
        background.add_task(-> {
          sleep 0.01
          events << :background
          raise "background failed"
        })
        FunApi::StreamingResponse.new { |stream| stream.write(resource.to_s) }
      end
    end

    _output, warnings = capture_io do
      Async do |task|
        task.with_timeout(1) do
          body = app.call(Rack::MockRequest.env_for("/stream"))[2]
          body.close
          app.run_shutdown_hooks
          assert_equal %i[background cleanup], events
          app.run_shutdown_hooks
        end
      end.wait
    end
    assert_includes warnings, "background failed"
    assert_includes warnings, "cleanup failed"
  end

  def test_completion_body_preserves_capabilities_and_finalizes_enumeration
    events = []
    original = Object.new
    original.define_singleton_method(:each) do |&block|
      block.call("one")
      block.call("two")
    end
    original.define_singleton_method(:to_path) { "/example/file" }
    original.define_singleton_method(:close) { events << :closed }
    body = FunApi::StreamingResponse::CompletionBody.new(original) { events << :complete }
    assert body.respond_to?(:each)
    refute body.respond_to?(:call)
    refute body.respond_to?(:to_ary)
    assert_equal "/example/file", body.to_path
    assert_equal ["one", "two"], body.each.to_a
    body.close
    assert_equal %i[closed complete], events

    events.clear
    body = FunApi::StreamingResponse::CompletionBody.new(original) { events << :complete }
    assert_raises(Errno::EPIPE) { body.each { raise Errno::EPIPE } }
    body.close
    assert_equal %i[closed complete], events
  end

  def test_completion_body_preserves_array_conversion_and_callable_shape
    events = []
    body = FunApi::StreamingResponse::CompletionBody.new(["hello"]) { events << :complete }
    assert_equal ["hello"], body.to_ary
    body.close
    assert_equal [:complete], events

    original = FunApi::StreamingResponse.new { |stream| stream.write("hello") }.to_response[2]
    body = FunApi::StreamingResponse::CompletionBody.new(original) {}
    assert body.respond_to?(:call)
    refute body.respond_to?(:each)
    refute body.respond_to?(:to_path)
    refute body.respond_to?(:to_ary)
  end

  def test_completion_waits_for_yielding_close_and_runs_even_if_close_fails
    events = []
    original = Object.new
    original.define_singleton_method(:close) do
      events << :closing
      sleep 0.01
      events << :closed
      raise "close failed"
    end
    body = FunApi::StreamingResponse::CompletionBody.new(original) { events << :complete }
    Async do |task|
      closer = task.async { assert_raises(RuntimeError) { body.close } }
      body.close
      assert_equal [:closing], events
      closer.wait
      body.close
    end.wait
    assert_equal %i[closing closed complete], events
  end

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
