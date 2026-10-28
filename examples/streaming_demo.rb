# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

# One app demonstrating all three streaming primitives:
#   GET  /count        -> chunked StreamingResponse
#   GET  /events       -> Server-Sent Events with a heartbeat
#   WS   /ws/:room     -> echo WebSocket

class RoomParams < FunApi::Model
  field :room, :string
end

app = FunApi::App.new(title: "Streaming Demo", version: "1.0.0") do |api|
  api.get "/count" do |_input, _req|
    FunApi::StreamingResponse.new(content_type: "text/plain") do |stream|
      5.times do |i|
        FunApi.sleep(0.2)
        stream.write("tick #{i}\n")
      end
    end
  end

  api.get "/events" do |_input, _req|
    FunApi::SSE.response(heartbeat: 10) do |sse|
      5.times do |i|
        FunApi.sleep(0.3)
        sse.send(data: {tick: i, at: Time.now.to_i}, event: "tick", id: i.to_s)
      end
      sse.send(data: "[DONE]", event: "done")
    end
  end

  api.websocket "/ws/:room", path: RoomParams do |socket, input|
    socket.write("joined room=#{input[:path][:room]}")
    while (message = socket.read)
      socket.write("echo: #{message.to_str}")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Streaming demo on http://localhost:9292"
  puts "  curl -N http://localhost:9292/count"
  puts "  curl -N http://localhost:9292/events"
  puts "  websocat ws://localhost:9292/ws/lobby"
  FunApi::Server::Falcon.start(app, port: 9292)
end
