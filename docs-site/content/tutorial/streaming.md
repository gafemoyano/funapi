---
title: "Tutorial 4: Streaming with SSE"
---

# Tutorial 4: Streaming with SSE

This is where FunApi's async foundation pays off. Because every request runs on
Falcon's fibered reactor, you can hold a connection open and push data as it
becomes available — perfect for progress updates, live feeds, and token-by-token
LLM responses.

We'll finish the tutorial by adding a Server-Sent Events (SSE) endpoint.

## Stream raw chunks

The simplest streaming primitive is `FunApi::StreamingResponse`. Return one from
a handler and write to the stream incrementally:

```ruby
api.get "/countdown" do |_input, _req|
  FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
    3.downto(1) do |n|
      stream.write("#{n}...\n")
      FunApi.sleep(1)          # non-blocking; the reactor serves others
    end
    stream.write("liftoff\n")
  end
end
```

Each `write` is flushed to the client immediately — the response body streams
rather than buffering.

## Server-Sent Events

`FunApi::SSE.response` formats the event stream for you. Add a live feed to the
blog:

```ruby
api.get "/posts/feed" do |_input, _req|
  FunApi::SSE.response(heartbeat: 15) do |sse|
    5.times do |i|
      sse.send(data: {post: "Update #{i}"}, event: "post", id: i.to_s)
      FunApi.sleep(1)
    end
  end
end
```

- `sse.send(data:, event:, id:, retry:)` writes a well-formed SSE event. A Hash
  `data:` is JSON-encoded; a String is sent as-is.
- `heartbeat: 15` sends a comment ping every 15 seconds so proxies keep the
  connection alive.

## Try it

```bash
$ curl -N http://localhost:3000/posts/feed
event: post
id: 0
data: {"post":"Update 0"}

event: post
id: 1
data: {"post":"Update 1"}
...
```

The `-N` flag disables curl's buffering so you see events arrive one at a time.

## Test streamed output

`FunApi::TestClient` can drive streaming endpoints without a server. Use
`stream` (or its alias `sse`) and assert on collected chunks or parsed events:

```ruby
def test_feed_emits_events
  client = FunApi::TestClient.new(Application)
  res = client.sse("/posts/feed")

  events = res.events
  assert_equal "post", events.first[:event]
  assert_equal "{\"post\":\"Update 0\"}", events.first[:data]
end
```

`res.chunks` gives the raw streamed pieces; `res.events` parses the SSE
protocol into an array of `{event:, id:, data:}` hashes.

## WebSockets

For bidirectional communication, register a WebSocket route:

```ruby
api.websocket "/ws/:room" do |socket, input|
  socket.write("joined #{input[:path][:room]}")
  while (message = socket.read)
    socket.write("echo: #{message}")
  end
end
```

See [Streaming, SSE & WebSockets](/docs/patterns/streaming) for the full
reference, including client-disconnect handling.

## You're done

You've built an API with validation, dependency injection, and streaming — and
tested all of it with `FunApi::TestClient`. From here:

- [Key Concepts](/docs/getting-started/key-concepts) — the mental model
- [Patterns](/docs/patterns/streaming) — deeper guides on each topic
- [Deployment](/docs/patterns/deployment) — going to production
