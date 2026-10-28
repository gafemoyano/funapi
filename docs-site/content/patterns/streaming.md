---
title: Streaming, SSE & WebSockets
---

# Streaming, SSE & WebSockets

FunApi is async-first, so long-lived, incremental responses are first-class.
Three primitives cover the common cases:

- `FunApi::StreamingResponse` — chunked bodies (files, NDJSON, progress).
- `FunApi::SSE` — Server-Sent Events with heartbeats.
- `api.websocket` — full-duplex WebSockets via `async-websocket`.

All three run each connection on its own fiber, so a slow stream never blocks
other requests.

## Streaming Responses

Return a `StreamingResponse` from a handler instead of `[payload, status]`. The
block receives a writable `stream`; write chunks with `<<` or `write`:

```ruby
api.get "/export" do |input, req|
  FunApi::StreamingResponse.new(content_type: "application/x-ndjson") do |stream|
    Report.each_row do |row|
      stream << "#{JSON.generate(row)}\n"
    end
  end
end
```

- `content_type:`, `status:`, and `headers:` are optional.
- No `content-length` is set; the connection stays open until the block returns.
- The block runs on its own fiber, so it can `FunApi.sleep`, await I/O, or spawn
  `FunApi.async` children while streaming.

### How it works

`StreamingResponse#to_response` returns a Rack 3 **callable body** — an object
that responds to `#call(stream)` (and not `#each`). Under Falcon this is wrapped
by `protocol-http`'s streaming body and driven chunk-by-chunk over the socket, so
bytes flush as you write them. Under a plain Rack test harness the same callable
runs eagerly against a buffer.

### Client disconnect

If the client goes away mid-stream, the write raises a broken-pipe error. FunApi
rescues these (`Errno::EPIPE`, `Errno::ECONNRESET`, `IOError`, and Falcon's
stream-closed error) and ends the block cleanly — the request task does not
crash. Other exceptions propagate as normal. Put resource cleanup in `ensure`
inside your block:

```ruby
api.get "/tail" do |input, req|
  FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
    file = File.open("/var/log/app.log")
    loop do
      line = file.gets or (FunApi.sleep(0.5); next)
      stream << line
    end
  ensure
    file&.close
  end
end
```

## Server-Sent Events (SSE)

`FunApi::SSE.response` builds a `StreamingResponse` with
`content-type: text/event-stream` and `cache-control: no-cache`, and hands your
block an SSE writer:

```ruby
api.get "/events" do |input, req|
  FunApi::SSE.response do |sse|
    sse.send(data: {tick: 1}, event: "tick", id: "1")
    sse.comment("keepalive")
  end
end
```

The writer formats events per the SSE spec:

- `sse.send(data:, event:, id:, retry:)` — `data` is JSON-encoded unless it is
  already a `String`. Multi-line data is split into multiple `data:` lines.
  `event`, `id`, and `retry` are optional.
- `sse.comment(text)` — emits a `: comment` line (useful as a keepalive).

### Heartbeats

Pass `heartbeat:` (seconds) and FunApi runs a child task that emits comment
pings while your block is idle. The heartbeat task is stopped automatically when
the block returns or the client disconnects:

```ruby
api.get "/events" do |input, req|
  FunApi::SSE.response(heartbeat: 15) do |sse|
    loop do
      sse.send(data: next_update, event: "update")
      FunApi.sleep(5)
    end
  end
end
```

## WebSockets

Register a WebSocket route with `api.websocket`. It registers a `GET` route that
upgrades the connection; non-upgrade requests to the same path get `426 Upgrade
Required`. Validated `path`/`query` arrive in `input` as usual:

```ruby
class RoomParams < FunApi::Model
  field :room, :string
end

api.websocket "/ws/:room", path: RoomParams do |socket, input|
  socket.write("joined #{input[:path][:room]}")

  while (message = socket.read)
    socket.write("echo: #{message.to_str}")
  end
end
```

The `socket` is an
[`async-websocket`](https://github.com/socketry/async-websocket) connection:

- `socket.read` blocks the fiber until the next message arrives and returns a
  message object (call `#to_str` for the text payload) — or `nil` when the peer
  closes, which ends the `while` loop.
- `socket.write(string)` sends a text frame. You can also send a
  `Protocol::WebSocket::Message`.
- The connection closes when the block returns.

### Connection lifecycle & backpressure

- One fiber per connection. A blocked `read` yields to the reactor, so idle
  sockets cost almost nothing.
- **Backpressure is honest, not automatic.** `socket.write` resolves as the
  socket accepts data; a slow consumer will slow your producing fiber rather than
  buffering unbounded memory. If you fan a firehose into a socket, add your own
  bounding (a bounded `Async::Queue`, dropping, or sampling).
- Always design `read` loops to exit on `nil`. Clean up per-connection resources
  in an `ensure` block.

> WebSockets need a real streaming server (Falcon). They do not work through the
> buffering `Rack::MockRequest` used in unit tests — see below.

## Testing

`StreamingResponse` and SSE bodies are callable, so unit tests can drive them
eagerly against a `StringIO`:

```ruby
env = Rack::MockRequest.env_for("/export")
status, headers, body = Async { app.call(env) }.wait
io = StringIO.new
body.call(io)
assert_equal expected, io.string
```

Real end-to-end streaming and WebSockets are exercised by booting a Falcon-
compatible `Async::HTTP::Server` on an ephemeral port and connecting with
`Async::HTTP::Client` / `Async::WebSocket::Client` (see
`test/test_streaming_integration.rb`).

## Flagship example

`examples/llm_proxy_demo.rb` is a ~30-line streaming LLM proxy: `POST /chat`
streams tokens from a stub model over SSE, and because each request runs on its
own fiber, many clients stream concurrently without blocking one another.
</content>
