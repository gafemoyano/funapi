# Template Rendering Implementation Plan

## Date: 2024-12-24

## Overview

Implement template rendering support for FunApi, inspired by FastAPI's Jinja2Templates feature. This enables FunApi to pair well with hypermedia libraries like HTMX for HTML-centric applications.

## Goals

1. Support ERB template rendering (Ruby stdlib)
2. Provide FastAPI-style convenience with Ruby idioms
3. Enable easy HTML response generation for HTMX-style applications
4. Keep implementation minimal and focused

## FastAPI Approach (Reference)

```python
from fastapi.templating import Jinja2Templates

templates = Jinja2Templates(directory="templates")

@app.get("/items/{id}", response_class=HTMLResponse)
async def read_item(request: Request, id: str):
    return templates.TemplateResponse(
        request=request, name="item.html", context={"id": id}
    )
```

## Template Engine

**Decision: ERB Only**

ERB (Embedded Ruby) is Ruby's built-in template engine:
- Zero additional dependencies
- Familiar to all Ruby developers
- Aligns with FunApi's minimal philosophy
- Same engine Rails uses (familiarity)

## API Design

**Decision: Option A - Explicit Templates Object**

```ruby
templates = FunApi::Templates.new(directory: 'templates')

app = FunApi::App.new do |api|
  api.get '/items/:id' do |input, req, task|
    templates.response('item.html.erb', id: input[:path]['id'])
  end
end
```

**Rationale:**
- Most explicit - clear where templates come from
- Templates object can be shared/reused across files
- Can have multiple template directories
- No App class changes needed
- Testable in isolation

## Implementation Design

### 1. Templates Class

```ruby
# lib/fun_api/templates.rb
module FunApi
  class Templates
    def initialize(directory:, layout: nil)
      @directory = Pathname.new(directory)
      @layout = layout
      @cache = {}
    end

    def render(name, layout: nil, **context)
      content = render_template(name, **context)
      
      layout_to_use = layout.nil? ? @layout : layout
      if layout_to_use
        render_template(layout_to_use, **context) { content }
      else
        content
      end
    end

    def response(name, status: 200, headers: {}, layout: nil, **context)
      html = render(name, layout: layout, **context)
      TemplateResponse.new(html, status: status, headers: headers)
    end

    def render_partial(name, **context)
      render_template(name, **context)
    end

    private

    def render_template(name, **context)
      template = load_template(name)
      binding_with_context = create_binding(context)
      template.result(binding_with_context) { yield if block_given? }
    end

    def load_template(name)
      path = @directory.join(name)
      raise TemplateNotFoundError.new(name) unless path.exist?

      @cache[name] ||= ERB.new(path.read, trim_mode: '-')
    end

    def create_binding(context)
      template_binding = TemplateContext.new(self, context).get_binding
      template_binding
    end
  end

  class TemplateContext
    def initialize(templates, context)
      @templates = templates
      context.each do |key, value|
        instance_variable_set("@#{key}", value)
        define_singleton_method(key) { value }
      end
    end

    def render_partial(name, **context)
      @templates.render_partial(name, **context)
    end

    def get_binding
      binding
    end
  end
end
```

### 2. TemplateResponse Class

```ruby
# lib/fun_api/template_response.rb
module FunApi
  class TemplateResponse
    attr_reader :body, :status, :headers

    def initialize(body, status: 200, headers: {})
      @body = body
      @status = status
      @headers = { 'content-type' => 'text/html; charset=utf-8' }.merge(headers)
    end

    def to_response
      [status, headers, [body]]
    end
  end
end
```

### 3. TemplateNotFoundError Exception

```ruby
# Add to lib/fun_api/exceptions.rb
class TemplateNotFoundError < StandardError
  attr_reader :template_name

  def initialize(template_name)
    @template_name = template_name
    super("Template not found: #{template_name}")
  end
end
```

### 4. Route Handler Integration

Modify `handle_async_route` in application.rb to detect TemplateResponse:

```ruby
def handle_async_route(req, path_params, body_schema, query_schema, response_schema, dependencies, &blk)
  # ... existing setup ...

  begin
    # ... validation ...

    payload, status = blk.call(input, req, current_task, **resolved_deps)

    # NEW: Detect TemplateResponse and return early
    if payload.is_a?(TemplateResponse)
      background_tasks.execute
      return payload.to_response
    end

    # ... existing JSON handling ...
  end
end
```

## File Structure

```
lib/fun_api/
├── templates.rb           # Templates class + TemplateContext
├── template_response.rb   # TemplateResponse class  
└── exceptions.rb          # Add TemplateNotFoundError

examples/
└── templates_demo.rb      # HTMX example

test/
├── test_templates.rb      # Template tests
└── fixtures/
    └── templates/         # Test templates
        ├── hello.html.erb
        ├── user.html.erb
        ├── with_partial.html.erb
        ├── _item.html.erb
        ├── layouts/
        │   └── application.html.erb
        └── items/
            └── show.html.erb
```

## Usage Examples

### Basic Template Rendering

```ruby
require 'fun_api'
require 'fun_api/templates'

templates = FunApi::Templates.new(directory: 'templates')

app = FunApi::App.new do |api|
  api.get '/' do |input, req, task|
    templates.response('index.html.erb', title: 'Home', message: 'Welcome!')
  end

  api.get '/users/:id' do |input, req, task|
    user = { id: input[:path]['id'], name: 'Alice' }
    templates.response('user.html.erb', user: user)
  end
end
```

### With Layouts

```ruby
templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'
)

app = FunApi::App.new do |api|
  api.get '/' do |input, req, task|
    templates.response('home.html.erb', title: 'Home')
  end
  
  # Override layout for specific route
  api.get '/plain' do |input, req, task|
    templates.response('plain.html.erb', layout: false, content: 'No layout')
  end
  
  # Use different layout
  api.get '/admin' do |input, req, task|
    templates.response('admin.html.erb', layout: 'layouts/admin.html.erb', title: 'Admin')
  end
end
```

```html
<!-- templates/layouts/application.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <title><%= title %></title>
</head>
<body>
  <header>My App</header>
  <main>
    <%= yield %>
  </main>
  <footer>Footer</footer>
</body>
</html>
```

```html
<!-- templates/home.html.erb -->
<h1>Welcome to <%= title %></h1>
<p>This is the home page.</p>
```

### With Partials

```ruby
api.get '/items' do |input, req, task|
  items = [
    { id: 1, name: 'Item 1' },
    { id: 2, name: 'Item 2' }
  ]
  templates.response('items/index.html.erb', items: items)
end
```

```html
<!-- templates/items/index.html.erb -->
<h1>Items</h1>
<ul>
  <% items.each do |item| %>
    <%= render_partial('items/_item.html.erb', item: item) %>
  <% end %>
</ul>
```

```html
<!-- templates/items/_item.html.erb -->
<li id="item-<%= item[:id] %>"><%= item[:name] %></li>
```

### With HTMX

```ruby
require 'fun_api'
require 'fun_api/templates'

templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'
)

ItemSchema = FunApi::Schema.define do
  required(:name).filled(:string)
end

app = FunApi::App.new do |api|
  api.get '/items' do |input, req, task|
    items = fetch_items
    templates.response('items/index.html.erb', items: items)
  end

  # Return partial (no layout) for HTMX requests
  api.post '/items', body: ItemSchema do |input, req, task|
    item = create_item(input[:body])
    templates.response('items/_item.html.erb', layout: false, item: item, status: 201)
  end

  api.delete '/items/:id' do |input, req, task|
    delete_item(input[:path]['id'])
    FunApi::TemplateResponse.new('', status: 200)
  end
end
```

## Implementation Phases

### Phase 1: Core Template Rendering (MVP)

1. `FunApi::Templates` class with ERB support
2. `FunApi::TemplateResponse` class
3. `TemplateNotFoundError` exception
4. Detection in route handler
5. Comprehensive tests with real examples

### Phase 2: Layouts and Partials

1. Layout support with `yield`
2. Per-route layout override (`layout: false`, `layout: 'other.html.erb'`)
3. `render_partial` helper within templates
4. Additional tests for layouts/partials

### Phase 3: Demo and Documentation

1. HTMX demo example
2. Update README with templates section

## Testing Strategy

### Test Fixtures

```
test/fixtures/templates/
├── hello.html.erb                    # Basic: "Hello, <%= name %>!"
├── user.html.erb                     # Object: "<p>User: <%= user[:name] %></p>"
├── items.html.erb                    # Loop: items.each
├── conditional.html.erb              # If/else
├── _item.html.erb                    # Partial
├── with_partial.html.erb             # Uses render_partial
├── with_yield.html.erb               # Has <%= yield %>
├── layouts/
│   ├── application.html.erb          # Standard layout with yield
│   └── admin.html.erb                # Alternative layout
└── nested/
    └── deep.html.erb                 # Nested directory test
```

### Test Cases

```ruby
class TestTemplates < Minitest::Test
  def setup
    @template_dir = Pathname.new(__dir__).join('fixtures/templates')
    @templates = FunApi::Templates.new(directory: @template_dir)
  end

  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  # === Basic Rendering ===

  def test_renders_template_with_string_variable
    html = @templates.render('hello.html.erb', name: 'World')
    assert_includes html, 'Hello, World!'
  end

  def test_renders_template_with_hash_variable
    html = @templates.render('user.html.erb', user: { id: 1, name: 'Alice' })
    assert_includes html, 'Alice'
  end

  def test_renders_template_with_array_and_loop
    html = @templates.render('items.html.erb', items: ['A', 'B', 'C'])
    assert_includes html, 'A'
    assert_includes html, 'B'
    assert_includes html, 'C'
  end

  def test_renders_template_with_conditionals
    html_true = @templates.render('conditional.html.erb', show: true)
    html_false = @templates.render('conditional.html.erb', show: false)
    
    assert_includes html_true, 'Visible'
    refute_includes html_false, 'Visible'
  end

  def test_renders_nested_template
    html = @templates.render('nested/deep.html.erb', value: 'test')
    assert_includes html, 'test'
  end

  # === TemplateResponse ===

  def test_response_returns_template_response
    response = @templates.response('hello.html.erb', name: 'Test')
    
    assert_instance_of FunApi::TemplateResponse, response
    assert_equal 200, response.status
    assert_equal 'text/html; charset=utf-8', response.headers['content-type']
    assert_includes response.body, 'Hello, Test!'
  end

  def test_response_with_custom_status
    response = @templates.response('hello.html.erb', status: 201, name: 'Created')
    assert_equal 201, response.status
  end

  def test_response_with_custom_headers
    response = @templates.response('hello.html.erb', 
      headers: { 'x-custom' => 'value' }, 
      name: 'Test')
    
    assert_equal 'value', response.headers['x-custom']
    assert_equal 'text/html; charset=utf-8', response.headers['content-type']
  end

  def test_template_response_to_response
    response = FunApi::TemplateResponse.new('<p>Test</p>', status: 201)
    status, headers, body = response.to_response
    
    assert_equal 201, status
    assert_equal 'text/html; charset=utf-8', headers['content-type']
    assert_equal ['<p>Test</p>'], body
  end

  # === Layouts ===

  def test_renders_with_default_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: 'layouts/application.html.erb'
    )
    
    html = templates.render('hello.html.erb', name: 'World', title: 'Test')
    
    assert_includes html, '<!DOCTYPE html>'
    assert_includes html, '<title>Test</title>'
    assert_includes html, 'Hello, World!'
  end

  def test_renders_without_layout_when_disabled
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: 'layouts/application.html.erb'
    )
    
    html = templates.render('hello.html.erb', layout: false, name: 'World')
    
    refute_includes html, '<!DOCTYPE html>'
    assert_includes html, 'Hello, World!'
  end

  def test_renders_with_different_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: 'layouts/application.html.erb'
    )
    
    html = templates.render('hello.html.erb', 
      layout: 'layouts/admin.html.erb', 
      name: 'World',
      title: 'Admin')
    
    assert_includes html, 'Admin Layout'
    assert_includes html, 'Hello, World!'
  end

  # === Partials ===

  def test_render_partial
    html = @templates.render('with_partial.html.erb', 
      items: [{ name: 'One' }, { name: 'Two' }])
    
    assert_includes html, 'One'
    assert_includes html, 'Two'
  end

  def test_render_partial_directly
    html = @templates.render_partial('_item.html.erb', item: { name: 'Direct' })
    assert_includes html, 'Direct'
  end

  # === Error Handling ===

  def test_raises_on_missing_template
    error = assert_raises(FunApi::TemplateNotFoundError) do
      @templates.render('nonexistent.html.erb')
    end
    
    assert_equal 'nonexistent.html.erb', error.template_name
    assert_includes error.message, 'Template not found'
  end

  def test_raises_on_missing_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: 'layouts/missing.html.erb'
    )
    
    assert_raises(FunApi::TemplateNotFoundError) do
      templates.render('hello.html.erb', name: 'Test')
    end
  end

  # === Caching ===

  def test_caches_compiled_templates
    @templates.render('hello.html.erb', name: 'First')
    @templates.render('hello.html.erb', name: 'Second')
    
    assert_equal 1, @templates.instance_variable_get(:@cache).size
  end

  # === Route Integration ===

  def test_integration_with_route_handler
    templates = FunApi::Templates.new(directory: @template_dir)
    
    app = FunApi::App.new do |api|
      api.get '/test' do |input, req, task|
        templates.response('hello.html.erb', name: 'Integration')
      end
    end

    res = async_request(app, :get, '/test')
    assert_equal 200, res.status
    assert_includes res.body, 'Hello, Integration!'
    assert_equal 'text/html; charset=utf-8', res['content-type']
  end

  def test_integration_with_path_params
    templates = FunApi::Templates.new(directory: @template_dir)
    
    app = FunApi::App.new do |api|
      api.get '/users/:id' do |input, req, task|
        templates.response('user.html.erb', 
          user: { id: input[:path]['id'], name: 'Test User' })
      end
    end

    res = async_request(app, :get, '/users/42')
    assert_equal 200, res.status
    assert_includes res.body, 'Test User'
  end

  def test_integration_with_custom_status
    templates = FunApi::Templates.new(directory: @template_dir)
    
    app = FunApi::App.new do |api|
      api.post '/items' do |input, req, task|
        templates.response('hello.html.erb', status: 201, name: 'Created')
      end
    end

    res = async_request(app, :post, '/items')
    assert_equal 201, res.status
  end

  def test_integration_with_layout
    templates = FunApi::Templates.new(
      directory: @template_dir,
      layout: 'layouts/application.html.erb'
    )
    
    app = FunApi::App.new do |api|
      api.get '/' do |input, req, task|
        templates.response('hello.html.erb', name: 'Home', title: 'My App')
      end
    end

    res = async_request(app, :get, '/')
    assert_equal 200, res.status
    assert_includes res.body, '<!DOCTYPE html>'
    assert_includes res.body, '<title>My App</title>'
    assert_includes res.body, 'Hello, Home!'
  end

  def test_json_routes_still_work
    templates = FunApi::Templates.new(directory: @template_dir)
    
    app = FunApi::App.new do |api|
      api.get '/html' do |input, req, task|
        templates.response('hello.html.erb', name: 'HTML')
      end
      
      api.get '/json' do |input, req, task|
        [{ message: 'JSON response' }, 200]
      end
    end

    html_res = async_request(app, :get, '/html')
    json_res = async_request(app, :get, '/json')
    
    assert_equal 'text/html; charset=utf-8', html_res['content-type']
    assert_equal 'application/json', json_res['content-type']
  end
end
```

## Decisions Log

| Question | Decision | Rationale |
|----------|----------|-----------|
| Template engine | ERB only | Stdlib, zero deps, familiar |
| API style | Option A (explicit) | More explicit, flexible, testable |
| Layouts | Phase 2 (important) | Core feature for real apps |
| Partials | Phase 2 (important) | Essential for HTMX patterns |
| URL helpers | Not implementing | Keep simple |
| Hot reload | Out of scope | Future consideration |
| Other engines | Out of scope | ERB sufficient |
| Auto-require | No | Opt-in, like middleware |

## Dependencies

None required - ERB is Ruby stdlib.

## Success Criteria

1. Can render ERB templates with context variables
2. Returns proper HTML content-type headers
3. Integrates seamlessly with existing route handlers
4. Layout support with yield
5. Partials with render_partial
6. No new dependencies
7. Follows FunApi's minimal philosophy
8. Comprehensive test coverage with real examples
9. JSON routes continue to work alongside HTML

## Comparison to FastAPI

| FastAPI | FunApi |
|---------|--------|
| `Jinja2Templates(directory="...")` | `Templates.new(directory: "...")` |
| `templates.TemplateResponse(...)` | `templates.response(...)` |
| Jinja2 | ERB (native Ruby) |
| `{{ variable }}` | `<%= variable %>` |
| `{% for item in items %}` | `<% items.each do \|item\| %>` |
| `{% include 'partial.html' %}` | `<%= render_partial('_partial.html.erb', ...) %>` |
| `{% extends 'base.html' %}` | `layout: 'layouts/base.html.erb'` |

## Next Steps

1. Create `lib/fun_api/templates.rb` (Templates + TemplateContext classes)
2. Create `lib/fun_api/template_response.rb`
3. Add `TemplateNotFoundError` to exceptions.rb
4. Modify `handle_async_route` to detect TemplateResponse
5. Create test fixtures (template files)
6. Write comprehensive tests
7. Create HTMX demo example
8. Update README

---

**Status:** Planning Complete - Ready for Implementation
**Estimated Effort:** ~3-4 hours (includes layouts and partials)
**Priority:** Medium-High (enables HTMX use cases)
