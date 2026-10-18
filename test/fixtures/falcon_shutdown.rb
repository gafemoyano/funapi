# frozen_string_literal: true

require "funapi"
require "funapi/server/falcon"
require "socket"

$stdout.sync = true
$stderr.sync = true

port = Integer(ARGV.fetch(0))
mode = ARGV.fetch(1)
handlers = %i[INT TERM].to_h do |signal|
  handler = proc { puts "previous #{signal}" }
  Signal.trap(signal, handler)
  [signal, handler]
end

app = FunApi::App.new do |api|
  api.get "/request" do
    Async::Task.current.defer_stop do
      puts "request active"
      if mode == "drain"
        sleep 0.2
        puts "request completed"
      else
        sleep
      end
    end
    [{ok: true}, 200]
  ensure
    sleep 0.02
    puts "request closed"
  end

  api.get "/stream" do
    FunApi::StreamingResponse.new do |stream|
      stream.write("first\n")
      puts "stream active"
      sleep
    ensure
      sleep 0.02
      puts "stream closed"
    end
  end

  api.on_shutdown do
    begin
      TCPSocket.new("127.0.0.1", port).close
      raise "listener still open"
    rescue Errno::ECONNREFUSED
      puts "listener closed"
    end
    puts "hook started"
    Async do |task|
      task.sleep(0.2)
      puts "async cleanup"
    end.wait
    raise "intentional hook failure" if mode == "stream"
  end

  api.on_shutdown { puts "last hook" }
end

FunApi::Server::Falcon.start(app, host: "127.0.0.1", port: port).wait
puts "adapter returned"
handlers.each do |signal, handler|
  restored = Signal.trap(signal, handler)
  raise "handler not restored: #{signal}" unless restored.equal?(handler)
  Process.kill(signal, Process.pid)
end
puts "finished"
