---
title: "Tutorial 2: Validation with Models"
---

# Tutorial 2: Request Validation with Models

Picking up from [Hello World](/docs/tutorial/hello-world), let's accept data
from clients. A `FunApi::Model` *is* your schema: one declaration gives you
request validation + coercion, response serialization/filtering, and OpenAPI —
all from the same class.

## Define a model

Add models to `app.rb`:

```ruby
require "funapi"

# What a client is allowed to send.
class CreatePost < FunApi::Model
  field :title, :string
  field :body, :string
  field :draft, :bool, default: true
end

# What a client is allowed to see (note: no internal fields).
class Post < FunApi::Model
  field :id, :integer
  field :title, :string
  field :body, :string
  field :draft, :bool
end
```

Fields support options like `optional: true`, `default:`, `nullable: true`,
`format:`, `enum:`, and `min:` / `max:`. See
[Validation](/docs/essential/validation) for the full reference.

## Use models on a route

Pass a model to `body:` for request validation and to `response_schema:` for
response filtering:

```ruby
Application = FunApi::App.new(title: "Blog") do |api|
  POSTS = []

  api.post "/posts", body: CreatePost, response_schema: Post do |input, _req|
    data = input[:body]                 # validated + coerced Hash
    post = {
      id: POSTS.length + 1,
      title: data[:title],
      body: data[:body],
      draft: data[:draft],
      secret_notes: "editor only"       # filtered out by Post
    }
    POSTS << post
    [post, 201]
  end

  api.get "/posts", response_schema: [Post] do |_input, _req|
    [POSTS, 200]                        # [Post] filters each element
  end
end
```

- `body: CreatePost` validates the incoming JSON before your handler runs.
- `response_schema: Post` filters the response so only declared fields go out —
  `secret_notes` never reaches the client.
- `response_schema: [Post]` applies the same filtering to each item in a list.

## Try it

```bash
# Valid — draft defaults to true, secret_notes is filtered out
$ curl -X POST http://localhost:3000/posts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Hello","body":"First post"}'
{"id":1,"title":"Hello","body":"First post","draft":true}

# Invalid — missing body
$ curl -X POST http://localhost:3000/posts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Hello"}'
{"detail":[{"loc":["body","body"],"msg":"is missing","type":"value_error"}]}
```

Validation failures return `422` with a FastAPI-style `detail` array — no code
of yours runs. Your `/docs` page now shows the request and response schemas.

## Test it

The scaffold's `test/app_test.rb` uses `FunApi::TestClient`, which drives the
app through Rack without booting a server and handles the async reactor for you:

```ruby
require_relative "test_helper"

class BlogTest < Minitest::Test
  def client
    @client ||= FunApi::TestClient.new(Application)
  end

  def test_creates_post_and_filters_response
    res = client.post("/posts", json: {title: "Hello", body: "First"})
    assert_equal 201, res.status
    assert_equal true, res.json[:draft]           # default applied
    refute res.json.key?(:secret_notes)           # filtered out
  end

  def test_missing_field_is_422
    res = client.post("/posts", json: {title: "Hello"})
    assert_equal 422, res.status
  end
end
```

```bash
ruby -Itest test/app_test.rb
```

## Next

[Tutorial 3: Dependency Injection →](/docs/tutorial/dependencies)
