# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "socket"
require "net/http"
require "timeout"
require "fileutils"
require "funapi/cli"

class TestCLI < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXE = File.join(ROOT, "exe", "funapi")
  LIB = File.join(ROOT, "lib")

  def run_cli(*args, chdir:)
    env = {"RUBYLIB" => LIB}
    Open3.capture2e(env, RbConfig.ruby, EXE, *args, chdir: chdir)
  end

  def with_scaffold
    Dir.mktmpdir do |dir|
      output, status = run_cli("new", "demo", chdir: dir)
      assert status.success?, "scaffold failed: #{output}"
      yield File.join(dir, "demo"), output
    end
  end

  def test_new_scaffolds_expected_files
    with_scaffold do |app_dir, _output|
      %w[app.rb config.ru Gemfile AGENTS.md README.md .gitignore
        test/test_helper.rb test/app_test.rb].each do |file|
        assert File.exist?(File.join(app_dir, file)), "missing #{file}"
      end

      app = File.read(File.join(app_dir, "app.rb"))
      assert_includes app, "FunApi::Model"
      assert_includes app, "Application = FunApi::App.new"

      test = File.read(File.join(app_dir, "test", "app_test.rb"))
      assert_includes test, "FunApi::TestClient"
    end
  end

  def test_new_refuses_to_overwrite_non_empty_directory
    with_scaffold do |app_dir, _output|
      output, status = run_cli("new", "demo", chdir: File.dirname(app_dir))
      refute status.success?
      assert_includes output, "refusing to overwrite"
    end
  end

  def test_routes_human_output
    with_scaffold do |app_dir, _output|
      output, status = run_cli("routes", chdir: app_dir)
      assert status.success?, output
      assert_includes output, "VERB"
      assert_includes output, "POST"
      assert_includes output, "/widgets"
      assert_includes output, "body=CreateWidget"
    end
  end

  def test_routes_json_output
    with_scaffold do |app_dir, _output|
      output, status = run_cli("routes", "--json", chdir: app_dir)
      assert status.success?, output
      routes = JSON.parse(output, symbolize_names: true)
      widgets = routes.find { |r| r[:path] == "/widgets" }
      assert_equal "POST", widgets[:verb]
      assert_equal "CreateWidget", widgets[:body_schema]
    end
  end

  def test_dev_boots_and_serves_docs
    with_scaffold do |app_dir, _output|
      port = free_port
      pid = spawn(
        {"RUBYLIB" => LIB},
        RbConfig.ruby, EXE, "dev", "--port", port.to_s, "--no-reload",
        chdir: app_dir, out: File::NULL, err: File::NULL
      )

      begin
        wait_until_ready(port)
        response = Net::HTTP.get_response(URI("http://localhost:#{port}/docs"))
        assert_equal "200", response.code
      ensure
        stop_process(pid)
      end
    end
  end

  def test_reloader_scans_ruby_files_and_ignores_noise
    require "funapi/cli"
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "app.rb"), "x")
      File.write(File.join(dir, "config.ru"), "run App")
      File.write(File.join(dir, "notes.txt"), "ignored extension")
      FileUtils.mkdir_p(File.join(dir, "vendor", "bundle"))
      File.write(File.join(dir, "vendor", "bundle", "dep.rb"), "ignored dir")
      FileUtils.mkdir_p(File.join(dir, "tmp"))
      File.write(File.join(dir, "tmp", "cache.rb"), "ignored dir")

      reloader = FunApi::CLI::Reloader.new(dir: dir)
      watched = reloader.scan.keys.map { |p| p.delete_prefix(dir + "/") }

      assert_includes watched, "app.rb"
      assert_includes watched, "config.ru"
      refute_includes watched, "notes.txt"
      refute(watched.any? { |p| p.start_with?("vendor/") })
      refute(watched.any? { |p| p.start_with?("tmp/") })
    end
  end

  def test_reloader_detects_changes
    require "funapi/cli"
    Dir.mktmpdir do |dir|
      target = File.join(dir, "app.rb")
      File.write(target, "v1")

      reloader = FunApi::CLI::Reloader.new(dir: dir)
      snapshot = reloader.scan

      refute reloader.changed?(snapshot)

      File.utime(Time.now + 5, Time.now + 5, target)
      assert reloader.changed?(snapshot)
    end
  end

  def stop_process(pid)
    Process.kill("TERM", pid)
    Timeout.timeout(5) { Process.wait(pid) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    begin
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  def free_port
    server = TCPServer.new("localhost", 0)
    port = server.addr[1]
    server.close
    port
  end

  def wait_until_ready(port)
    40.times do
      TCPSocket.new("localhost", port).close
      return
    rescue Errno::ECONNREFUSED
      sleep(0.05)
    end
    raise "dev server did not become ready on port #{port}"
  end
end
