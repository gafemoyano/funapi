# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

# Streaming LLM proxy in ~30 lines: POST /chat streams tokens back over SSE.
# The stub "LLM" yields words with small delays; because each request runs on
# its own fiber, ten clients stream at once without blocking one another.

def stub_llm(prompt)
  return enum_for(:stub_llm, prompt) unless block_given?

  "You said: #{prompt}. Here is a streamed reply, one token at a time.".split(" ").each do |word|
    FunApi.sleep(0.08)
    yield word
  end
end

class ChatRequest < FunApi::Model
  field :prompt, :string, description: "The user's message"
end

app = FunApi::App.new(title: "LLM Proxy", version: "1.0.0") do |api|
  api.post "/chat", body: ChatRequest do |input, _req|
    prompt = input[:body][:prompt]

    FunApi::SSE.response(heartbeat: 15) do |sse|
      stub_llm(prompt) { |token| sse.send(data: token, event: "token") }
      sse.send(data: "[DONE]", event: "done")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Starting LLM proxy on http://localhost:9292"
  puts "Try, in several terminals at once:"
  puts %(  curl -N -X POST http://localhost:9292/chat -H 'content-type: application/json' -d '{"prompt":"hello"}')
  FunApi::Server::Falcon.start(app, port: 9292)
end
