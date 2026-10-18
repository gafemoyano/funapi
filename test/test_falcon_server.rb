# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "socket"
require "timeout"

class TestFalconServer < Minitest::Test
  def test_signals_cancel_requests_before_async_shutdown_hooks_and_restore_handlers
    %w[INT TERM].product(%w[idle stream request drain]).each do |signal, mode|
      output = run_server(signal, mode)

      ["listener closed", "hook started", "async cleanup", "last hook", "adapter returned", "previous INT", "previous TERM", "finished"].each do |event|
        assert_equal 1, output.lines.count { |line| line.chomp == event }, output
      end
      refute_includes output, "ThreadError"
      refute_includes output, "listener still open"
      assert_operator output.index("async cleanup"), :<, output.index("last hook"), output
      assert_operator output.index("last hook"), :<, output.index("adapter returned"), output

      if mode == "stream"
        assert_equal 1, output.lines.count { |line| line.chomp == "stream closed" }, output
        assert_operator output.index("stream closed"), :<, output.index("hook started"), output
        assert_includes output, "Shutdown hook failed: intentional hook failure"
      end
      if %w[request drain].include?(mode)
        assert_equal 1, output.lines.count { |line| line.chomp == "request closed" }, output
        assert_operator output.index("request closed"), :<, output.index("hook started"), output
      end
      assert_includes output, "request completed" if mode == "drain"
    end
  end

  private

  def run_server(signal, mode)
    port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
    output = +""
    connection = nil

    Open3.popen2e(RbConfig.ruby, "-Ilib", "test/fixtures/falcon_shutdown.rb", port.to_s, mode) do |input, pipe, process|
      input.close
      begin
        Timeout.timeout(10) do
          read_until(pipe, output, "Press Ctrl+C to stop")
          unless mode == "idle"
            path = (mode == "stream") ? "stream" : "request"
            connection = TCPSocket.new("127.0.0.1", port)
            connection.write("GET /#{path} HTTP/1.1\r\nHost: localhost\r\n\r\n")
            read_until(pipe, output, "#{path} active")
          end

          Process.kill(signal, process.pid)
          read_until(pipe, output, "hook started")
          Process.kill(signal, process.pid)
          output << pipe.read
          assert process.value.success?, "#{signal}/#{mode}: #{output}"
        end
      rescue Timeout::Error
        flunk "#{signal}/#{mode} timed out: #{output}"
      ensure
        connection&.close
        if process.alive?
          Process.kill("KILL", process.pid)
          process.join
        end
      end
    end

    output
  end

  def read_until(pipe, output, expected)
    while (line = pipe.gets)
      output << line
      return if line.chomp == expected
    end
    flunk "Missing #{expected.inspect}: #{output}"
  end
end
