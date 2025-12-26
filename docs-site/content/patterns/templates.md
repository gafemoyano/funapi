---
title: Templates
---

# Templates

Render ERB templates for HTML responses. Perfect for HTMX-powered applications.

## Setup

```ruby
require 'funapi/templates'

templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'  # Optional default layout
)
```

## Basic Rendering

Return a `TemplateResponse` from your handler:

```ruby
api.get '/' do |input, req, task|
  templates.response('home.html.erb', title: 'Home', user: current_user)
end
```

Template (`templates/home.html.erb`):

```erb
<h1>Welcome, <%= user[:name] %>!</h1>
<p>This is the home page.</p>
```

## Layouts

### Default Layout

Set a default layout in the constructor:

```ruby
templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'
)
```

Layout (`templates/layouts/application.html.erb`):

```erb
<!DOCTYPE html>
<html>
<head>
  <title><%= title %></title>
</head>
<body>
  <nav>...</nav>
  
  <main>
    <%= yield_content %>
  </main>
  
  <footer>...</footer>
</body>
</html>
```

Use `yield_content` to insert the template content.

### Disabling Layout

For partials or HTMX responses, disable the layout:

```ruby
api.post '/items' do |input, req, task|
  item = create_item(input[:body])
  templates.response('items/_item.html.erb', layout: false, item: item, status: 201)
end
```

### Different Layouts

Use `with_layout` for route groups:

```ruby
templates = FunApi::Templates.new(directory: 'templates')

public_templates = templates.with_layout('layouts/public.html.erb')
admin_templates = templates.with_layout('layouts/admin.html.erb')

api.get '/' do |input, req, task|
  public_templates.response('home.html.erb', title: 'Home')
end

api.get '/admin' do |input, req, task|
  admin_templates.response('admin/dashboard.html.erb', title: 'Dashboard')
end
```

## Partials

Render partials within templates:

```erb
<!-- templates/items/index.html.erb -->
<ul id="items">
  <% items.each do |item| %>
    <%= render_partial('items/_item.html.erb', item: item) %>
  <% end %>
</ul>
```

```erb
<!-- templates/items/_item.html.erb -->
<li id="item-<%= item[:id] %>">
  <%= item[:name] %>
</li>
```

## With HTMX

FunApi templates work great with HTMX:

```ruby
# Full page with layout
api.get '/items' do |input, req, task|
  items = fetch_items
  templates.response('items/index.html.erb', items: items)
end

# Partial for HTMX insertion
api.post '/items', body: ItemSchema do |input, req, task|
  item = create_item(input[:body])
  templates.response('items/_item.html.erb', layout: false, item: item, status: 201)
end

# Empty response for HTMX delete
api.delete '/items/:id' do |input, req, task|
  delete_item(input[:path]['id'])
  FunApi::TemplateResponse.new('')
end
```

Template with HTMX:

```erb
<form hx-post="/items" hx-target="#items" hx-swap="beforeend">
  <input type="text" name="name" placeholder="New item">
  <button type="submit">Add</button>
</form>

<ul id="items">
  <% items.each do |item| %>
    <%= render_partial('items/_item.html.erb', item: item) %>
  <% end %>
</ul>
```

## Template Variables

Pass any variables as keyword arguments:

```ruby
templates.response('page.html.erb',
  title: 'My Page',
  user: current_user,
  items: items,
  flash: { notice: 'Success!' }
)
```

Access them directly in templates:

```erb
<h1><%= title %></h1>
<p>Hello, <%= user[:name] %></p>

<% if flash[:notice] %>
  <div class="notice"><%= flash[:notice] %></div>
<% end %>
```

## Custom Status and Headers

```ruby
templates.response('error.html.erb',
  status: 404,
  headers: { 'X-Custom' => 'value' },
  message: 'Not found'
)
```
