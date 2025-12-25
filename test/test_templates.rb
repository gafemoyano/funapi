# frozen_string_literal: true

require "test_helper"
require "fun_api/templates"
require "pathname"

class TestTemplates < Minitest::Test
  def setup
    @template_dir = Pathname.new(__dir__).join("fixtures/templates")
    @templates = FunApi::Templates.new(directory: @template_dir)
  end

  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_renders_template_with_string_variable
    html = @templates.render("hello.html.erb", name: "World")
    assert_includes html, "Hello, World!"
  end

  def test_renders_template_with_hash_variable
    html = @templates.render("user.html.erb", user: {id: 1, name: "Alice"})
    assert_includes html, "User 1"
    assert_includes html, "Name: Alice"
  end

  def test_renders_template_with_array_and_loop
    html = @templates.render("items.html.erb", items: ["A", "B", "C"])
    assert_includes html, "<li>A</li>"
    assert_includes html, "<li>B</li>"
    assert_includes html, "<li>C</li>"
  end

  def test_renders_template_with_conditionals_true
    html = @templates.render("conditional.html.erb", show: true)
    assert_includes html, "Visible"
    refute_includes html, "Hidden"
  end

  def test_renders_template_with_conditionals_false
    html = @templates.render("conditional.html.erb", show: false)
    assert_includes html, "Hidden"
    refute_includes html, "Visible"
  end

  def test_renders_nested_template
    html = @templates.render("nested/deep.html.erb", value: "test")
    assert_includes html, "Nested value: test"
  end

  def test_response_returns_template_response
    response = @templates.response("hello.html.erb", name: "Test")

    assert_instance_of FunApi::TemplateResponse, response
    assert_equal 200, response.status
    assert_equal "text/html; charset=utf-8", response.headers["content-type"]
    assert_includes response.body, "Hello, Test!"
  end

  def test_response_with_custom_status
    response = @templates.response("hello.html.erb", status: 201, name: "Created")
    assert_equal 201, response.status
  end

  def test_response_with_custom_headers
    response = @templates.response("hello.html.erb",
      headers: {"x-custom" => "value"},
      name: "Test")

    assert_equal "value", response.headers["x-custom"]
    assert_equal "text/html; charset=utf-8", response.headers["content-type"]
  end

  def test_template_response_to_response
    response = FunApi::TemplateResponse.new("<p>Test</p>", status: 201)
    status, headers, body = response.to_response

    assert_equal 201, status
    assert_equal "text/html; charset=utf-8", headers["content-type"]
    assert_equal ["<p>Test</p>"], body
  end

  def test_renders_with_default_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    html = templates.render("hello.html.erb", name: "World", title: "Test Page")

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "<title>Test Page</title>"
    assert_includes html, "Hello, World!"
    assert_includes html, "My App Header"
    assert_includes html, "My App Footer"
  end

  def test_renders_without_layout_when_disabled
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    html = templates.render("hello.html.erb", layout: false, name: "World")

    refute_includes html, "<!DOCTYPE html>"
    refute_includes html, "My App Header"
    assert_includes html, "Hello, World!"
  end

  def test_renders_with_different_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    html = templates.render("hello.html.erb",
      layout: "layouts/admin.html.erb",
      name: "World",
      title: "Admin Page")

    assert_includes html, "Admin Layout"
    assert_includes html, "Admin - Admin Page"
    assert_includes html, "Hello, World!"
    refute_includes html, "My App Footer"
  end

  def test_render_partial
    html = @templates.render("with_partial.html.erb",
      items: [{name: "One"}, {name: "Two"}])

    assert_includes html, "One"
    assert_includes html, "Two"
    assert_includes html, '<li class="item">'
  end

  def test_render_partial_directly
    html = @templates.render_partial("_item.html.erb", item: {name: "Direct"})
    assert_includes html, "Direct"
    assert_includes html, '<li class="item">'
  end

  def test_render_partial_in_subdirectory
    html = @templates.render("items/index.html.erb",
      items: [{id: 1, name: "First"}, {id: 2, name: "Second"}])

    assert_includes html, "Items List"
    assert_includes html, 'id="item-1"'
    assert_includes html, 'id="item-2"'
    assert_includes html, "First"
    assert_includes html, "Second"
  end

  def test_raises_on_missing_template
    error = assert_raises(FunApi::TemplateNotFoundError) do
      @templates.render("nonexistent.html.erb")
    end

    assert_equal "nonexistent.html.erb", error.template_name
    assert_includes error.message, "Template not found"
  end

  def test_raises_on_missing_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/missing.html.erb"
    )

    assert_raises(FunApi::TemplateNotFoundError) do
      templates.render("hello.html.erb", name: "Test")
    end
  end

  def test_raises_on_missing_partial
    assert_raises(FunApi::TemplateNotFoundError) do
      @templates.render_partial("_missing.html.erb", item: {})
    end
  end

  def test_caches_compiled_templates
    @templates.render("hello.html.erb", name: "First")
    @templates.render("hello.html.erb", name: "Second")

    assert_equal 1, @templates.instance_variable_get(:@cache).size
  end

  def test_caches_multiple_templates
    @templates.render("hello.html.erb", name: "Test")
    @templates.render("user.html.erb", user: {id: 1, name: "User"})
    @templates.render("hello.html.erb", name: "Again")

    assert_equal 2, @templates.instance_variable_get(:@cache).size
  end

  def test_integration_with_route_handler
    templates = FunApi::Templates.new(directory: @template_dir)

    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, _task|
        templates.response("hello.html.erb", name: "Integration")
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    assert_includes res.body, "Hello, Integration!"
    assert_equal "text/html; charset=utf-8", res["content-type"]
  end

  def test_integration_with_path_params
    templates = FunApi::Templates.new(directory: @template_dir)

    app = FunApi::App.new do |api|
      api.get "/users/:id" do |input, _req, _task|
        templates.response("user.html.erb",
          user: {id: input[:path]["id"], name: "Test User"})
      end
    end

    res = async_request(app, :get, "/users/42")
    assert_equal 200, res.status
    assert_includes res.body, "User 42"
    assert_includes res.body, "Test User"
  end

  def test_integration_with_custom_status
    templates = FunApi::Templates.new(directory: @template_dir)

    app = FunApi::App.new do |api|
      api.post "/items" do |_input, _req, _task|
        templates.response("hello.html.erb", status: 201, name: "Created")
      end
    end

    res = async_request(app, :post, "/items")
    assert_equal 201, res.status
    assert_includes res.body, "Hello, Created!"
  end

  def test_integration_with_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    app = FunApi::App.new do |api|
      api.get "/" do |_input, _req, _task|
        templates.response("hello.html.erb", name: "Home", title: "My App")
      end
    end

    res = async_request(app, :get, "/")
    assert_equal 200, res.status
    assert_includes res.body, "<!DOCTYPE html>"
    assert_includes res.body, "<title>My App</title>"
    assert_includes res.body, "Hello, Home!"
  end

  def test_integration_layout_disabled_for_partial
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    app = FunApi::App.new do |api|
      api.post "/items" do |_input, _req, _task|
        templates.response("_item.html.erb",
          layout: false,
          item: {name: "New Item"},
          status: 201)
      end
    end

    res = async_request(app, :post, "/items")
    assert_equal 201, res.status
    refute_includes res.body, "<!DOCTYPE html>"
    assert_includes res.body, "New Item"
  end

  def test_json_routes_still_work
    templates = FunApi::Templates.new(directory: @template_dir)

    app = FunApi::App.new do |api|
      api.get "/html" do |_input, _req, _task|
        templates.response("hello.html.erb", name: "HTML")
      end

      api.get "/json" do |_input, _req, _task|
        [{message: "JSON response"}, 200]
      end
    end

    html_res = async_request(app, :get, "/html")
    json_res = async_request(app, :get, "/json")

    assert_equal "text/html; charset=utf-8", html_res["content-type"]
    assert_equal "application/json", json_res["content-type"]
    assert_includes html_res.body, "Hello, HTML!"
    assert_includes json_res.body, "JSON response"
  end

  def test_template_with_complex_data
    templates = FunApi::Templates.new(directory: @template_dir)

    app = FunApi::App.new do |api|
      api.get "/items" do |_input, _req, _task|
        items = [
          {id: 1, name: "First Item"},
          {id: 2, name: "Second Item"},
          {id: 3, name: "Third Item"}
        ]
        templates.response("items/index.html.erb", items: items)
      end
    end

    res = async_request(app, :get, "/items")
    assert_equal 200, res.status
    assert_includes res.body, "Items List"
    assert_includes res.body, "First Item"
    assert_includes res.body, "Second Item"
    assert_includes res.body, "Third Item"
    assert_includes res.body, 'id="item-1"'
    assert_includes res.body, 'id="item-2"'
    assert_includes res.body, 'id="item-3"'
  end

  def test_template_response_empty_body
    response = FunApi::TemplateResponse.new("")
    status, headers, body = response.to_response

    assert_equal 200, status
    assert_equal [""], body
    assert_equal "text/html; charset=utf-8", headers["content-type"]
  end

  def test_multiple_templates_instances
    templates1 = FunApi::Templates.new(directory: @template_dir)
    templates2 = FunApi::Templates.new(
      directory: @template_dir,
      layout: "layouts/application.html.erb"
    )

    html1 = templates1.render("hello.html.erb", name: "No Layout")
    html2 = templates2.render("hello.html.erb", name: "With Layout", title: "Test")

    refute_includes html1, "<!DOCTYPE html>"
    assert_includes html2, "<!DOCTYPE html>"
    assert_includes html1, "Hello, No Layout!"
    assert_includes html2, "Hello, With Layout!"
  end

  def test_with_layout_returns_scoped_templates
    scoped = @templates.with_layout("layouts/application.html.erb")

    assert_instance_of FunApi::ScopedTemplates, scoped
  end

  def test_with_layout_uses_specified_layout
    scoped = @templates.with_layout("layouts/application.html.erb")
    html = scoped.render("hello.html.erb", name: "Scoped", title: "Test")

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "<title>Test</title>"
    assert_includes html, "Hello, Scoped!"
  end

  def test_with_layout_response
    scoped = @templates.with_layout("layouts/application.html.erb")
    response = scoped.response("hello.html.erb", name: "Scoped", title: "Test")

    assert_instance_of FunApi::TemplateResponse, response
    assert_includes response.body, "<!DOCTYPE html>"
    assert_includes response.body, "Hello, Scoped!"
  end

  def test_with_layout_can_override_layout
    scoped = @templates.with_layout("layouts/application.html.erb")
    html = scoped.render("hello.html.erb", layout: "layouts/admin.html.erb", name: "Admin", title: "Admin")

    assert_includes html, "Admin Layout"
    refute_includes html, "My App Footer"
  end

  def test_with_layout_can_disable_layout
    scoped = @templates.with_layout("layouts/application.html.erb")
    html = scoped.render("hello.html.erb", layout: false, name: "No Layout")

    refute_includes html, "<!DOCTYPE html>"
    assert_includes html, "Hello, No Layout!"
  end

  def test_with_layout_render_partial
    scoped = @templates.with_layout("layouts/application.html.erb")
    html = scoped.render_partial("_item.html.erb", item: {name: "Partial"})

    refute_includes html, "<!DOCTYPE html>"
    assert_includes html, "Partial"
  end

  def test_with_layout_integration
    admin_templates = @templates.with_layout("layouts/admin.html.erb")

    app = FunApi::App.new do |api|
      api.get "/admin" do |_input, _req, _task|
        admin_templates.response("hello.html.erb", name: "Admin Page", title: "Admin")
      end
    end

    res = async_request(app, :get, "/admin")
    assert_equal 200, res.status
    assert_includes res.body, "Admin Layout"
    assert_includes res.body, "Hello, Admin Page!"
  end
end
