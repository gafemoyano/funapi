# frozen_string_literal: true

require "test_helper"
require "funapi/test_client"

class TestTestClient < Minitest::Test
  def build_app
    user_schema = FunApi::Schema.define do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end

    FunApi::App.new do |api|
      api.get "/hello" do |input, _req|
        [{message: "Hello, #{input[:query]["name"] || "world"}"}, 200]
      end

      api.get "/users/:id" do |input, _req|
        [{id: input[:path][:id]}, 200]
      end

      api.post "/users", body: user_schema do |input, _req|
        [{created: input[:body]}, 201]
      end

      api.put "/users/:id" do |input, _req|
        [{updated: input[:path][:id], attrs: input[:body]}, 200]
      end

      api.delete "/users/:id" do |input, _req|
        [{deleted: input[:path][:id]}, 200]
      end

      api.get "/whoami" do |input, _req|
        [{auth: input[:headers]["authorization"]}, 200]
      end

      api.get "/stream" do |_input, _req|
        FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
          3.times { |i| stream.write("chunk#{i}\n") }
        end
      end

      api.get "/events" do |_input, _req|
        FunApi::SSE.response do |sse|
          sse.send(data: {tick: 1}, event: "tick", id: "1")
          sse.send(data: "bye")
        end
      end
    end
  end

  def client
    @client ||= FunApi::TestClient.new(build_app)
  end

  def test_get_returns_response_with_status_and_json
    res = client.get("/hello")
    assert_equal 200, res.status
    assert_equal({message: "Hello, world"}, res.json)
    assert_equal "application/json", res.content_type
  end

  def test_get_with_query_params
    res = client.get("/hello", params: {name: "Ada"})
    assert_equal({message: "Hello, Ada"}, res.json)
  end

  def test_get_with_path_param
    res = client.get("/users/42")
    assert_equal({id: "42"}, res.json)
  end

  def test_post_with_json_body
    res = client.post("/users", json: {name: "Tess", email: "tess@example.com"})
    assert_equal 201, res.status
    assert_equal "Tess", res.json[:created][:name]
  end

  def test_post_validation_failure
    res = client.post("/users", json: {name: "Tess"})
    assert_equal 422, res.status
    assert(res.json[:detail].any? { |e| e[:loc].include?("email") })
  end

  def test_put_and_delete
    put = client.put("/users/7", json: {email: "x@y.com"})
    assert_equal "7", put.json[:updated]

    del = client.delete("/users/7")
    assert_equal "7", del.json[:deleted]
  end

  def test_headers_are_forwarded
    res = client.get("/whoami", headers: {"Authorization" => "Bearer token"})
    assert_equal "Bearer token", res.json[:auth]
  end

  def test_headers_accessor_is_case_insensitive
    res = client.get("/hello")
    assert_equal "application/json", res["Content-Type"]
  end

  def test_stream_collects_chunks
    res = client.stream("/stream")
    assert_equal 200, res.status
    assert_equal "chunk0\nchunk1\nchunk2\n", res.body
    assert_equal 3, res.chunks.length
  end

  def test_sse_events_parsed
    res = client.sse("/events")
    events = res.events
    assert_equal "tick", events[0][:event]
    assert_equal "1", events[0][:id]
    assert_equal "{\"tick\":1}", events[0][:data]
    assert_equal "bye", events[1][:data]
  end

  def test_works_inside_running_reactor
    result = Async do
      FunApi::TestClient.new(build_app).get("/hello").status
    end.wait
    assert_equal 200, result
  end
end
