# Response Schema Feature

## Overview

The `response_schema` feature allows you to validate and filter response data before sending it to clients, similar to FastAPI's `response_model`. This ensures:

1. **Data Security** - Sensitive fields (like passwords) are automatically filtered from responses
2. **Data Validation** - Responses are validated to ensure your app returns correct data structure
3. **Documentation** - Response schemas will be used for automatic API documentation generation (future)

## Basic Usage

### Option 1: Using `response_schema` Parameter

```ruby
# Define input and output schemas
UserInput = FunApi::Schema.define do
  required(:username).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

UserOutput = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
  # Note: password NOT included
end

# Use in route
api.post '/users', 
  body: UserInput,
  response_schema: UserOutput do |input, req, task|
    # Handler returns full user object with password
    user = {
      id: 1,
      username: input[:body][:username],
      email: input[:body][:email],
      password: input[:body][:password],  # This will be filtered!
      age: input[:body][:age]
    }
    
    [user, 201]
    # Response sent to client:
    # { "id": 1, "username": "...", "email": "...", "age": ... }
    # Password is automatically removed!
end
```

### Option 2: Return Schema Result Directly

You can also call the schema in your handler and return the result directly:

```ruby
api.post '/users', body: UserInput do |input, req, task|
  user_data = {
    id: 1,
    username: input[:body][:username],
    email: input[:body][:email],
    password: input[:body][:password],
    age: input[:body][:age]
  }
  
  # Call schema and return result
  result = UserOutput.call(user_data)
  [result, 201]
  # Framework automatically extracts result.to_h
  # Password is filtered by the schema!
end
```

This approach gives you more flexibility in the handler:

```ruby
api.post '/users', body: UserInput do |input, req, task|
  user_data = {
    id: 1,
    username: input[:body][:username],
    email: input[:body][:email],
    password: input[:body][:password],
    age: input[:body][:age]
  }
  
  # Validate and filter in handler
  result = UserOutput.call(user_data)
  
  # Check if validation succeeded
  if result.success?
    [result, 201]
  else
    # Handle validation errors
    raise FunApi::HTTPException.new(
      status_code: 500,
      detail: "Invalid response data: #{result.errors.to_h}"
    )
  end
end
```

### Array Responses

You can use both approaches with arrays too:

```ruby
ItemSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:price).filled(:float)
end

# Option 1: Using response_schema parameter
api.post '/items/batch',
  body: [ItemSchema],
  response_schema: [ItemSchema] do |input, req, task|
    
  items = input[:body].map do |item_data|
    {
      name: item_data[:name],
      price: item_data[:price],
      internal_cost: item_data[:price] * 0.5  # This will be filtered!
    }
  end
  
  [items, 201]
  # internal_cost is filtered from all items in the response
end

# Option 2: Return array of schema results
api.post '/items/batch', body: [ItemSchema] do |input, req, task|
  results = input[:body].map do |item_data|
    data = {
      name: item_data[:name],
      price: item_data[:price],
      internal_cost: item_data[:price] * 0.5
    }
    ItemSchema.call(data)  # Returns schema result
  end
  
  [results, 201]
  # Framework converts array of results to array of hashes
  # internal_cost is filtered by schema
end
```

## How It Works

### 1. Request Flow

```
Request → Input Validation → Handler Execution → Response Validation → Client
                ↓                                          ↓
            body/query schema                      response_schema
            (validates input)                      (validates & filters output)
```

### 2. Validation Behavior

**For Responses:**
- ✅ **Missing required fields** → Returns 500 error (your app code is broken)
- ✅ **Extra fields** → Automatically filtered out (security)
- ✅ **Wrong types** → Returns 500 error (your app code is broken)

**For Requests (body/query):**
- ✅ **Missing required fields** → Returns 422 error (client error)
- ✅ **Wrong types** → Returns 422 error (client error)

### 3. Array Support

Both input validation and response validation support arrays:

```ruby
# Input array validation
api.post '/items', body: [ItemSchema] do |input, req, task|
  # input[:body] is an array of validated hashes
  items = input[:body].map { |item| create_item(item) }
  [items, 201]
end

# Output array validation
api.get '/items', response_schema: [ItemSchema] do |input, req, task|
  items = fetch_all_items()  # Returns array
  [items, 200]  # Each item validated and filtered
end
```

## Examples

### Example 1: Filtering Sensitive Data

```ruby
# Schema with password
UserWithPassword = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
  required(:password).filled(:string)
end

# Public schema without password
PublicUser = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
end

api.get '/users/:id', response_schema: PublicUser do |input, req, task|
  # Fetch from database returns password
  user = db.fetch_user(input[:path]['id'])
  # { id: 1, username: "john", password: "hashed_password" }
  
  [user, 200]
  # Client receives: { "id": 1, "username": "john" }
  # Password automatically filtered!
end
```

### Example 2: Batch Operations

```ruby
CreateUser = FunApi::Schema.define do
  required(:username).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
end

UserResponse = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
  required(:email).filled(:string)
end

api.post '/users/batch',
  body: [CreateUser],
  response_schema: [UserResponse] do |input, req, task|
    
  users = input[:body].map do |user_data|
    create_user(user_data)  # Returns user with password
  end
  
  [users, 201]
  # All passwords filtered from response array
end
```

### Example 3: Optional Response Schema

`response_schema` is optional. If not provided, data is returned as-is:

```ruby
# Without response_schema - returns all fields
api.get '/debug/user/:id' do |input, req, task|
  user = fetch_user(input[:path]['id'])
  [user, 200]  # Returns everything, including sensitive fields
end

# With response_schema - filters fields
api.get '/users/:id', response_schema: UserOutput do |input, req, task|
  user = fetch_user(input[:path]['id'])
  [user, 200]  # Filters according to schema
end
```

## Error Handling

### Response Validation Errors (500)

If your handler returns data that doesn't match the `response_schema`, a 500 error is returned:

```ruby
api.get '/users/:id', response_schema: UserOutput do |input, req, task|
  # Oops! Missing required 'id' field
  user = { username: "john", email: "john@example.com" }
  [user, 200]
end

# Client receives:
# Status: 500
# { "detail": "Response validation failed: {id: [\"is missing\"]}" }
```

This indicates a **bug in your application code** - you promised to return data with certain fields but didn't.

### Input Validation Errors (422)

Input validation errors return 422 (client error):

```ruby
api.post '/users', body: UserInput do |input, req, task|
  # ... handler code
end

# Client sends invalid data:
# POST /users { "username": "john" }  // missing email

# Response:
# Status: 422
# {
#   "detail": [
#     {
#       "loc": ["body", "email"],
#       "msg": "is missing",
#       "type": "value_error"
#     }
#   ]
# }
```

## Best Practices

1. **Choose the right approach**:
   - Use `response_schema:` parameter when you want automatic validation
   - Return schema results directly when you need more control or conditional logic
   - Combine both for maximum safety (schema result + response_schema validation)

2. **Always filter sensitive data** - Use response_schema or schema results to prevent data leaks

3. **Separate input and output schemas** - Often input requires password, output doesn't

4. **Reuse schemas** - Define once, use for both validation and documentation

5. **Use arrays consistently** - `[Schema]` for both input and output arrays

6. **Let validation fail** - Don't catch response validation errors, they indicate bugs

## Implementation Details

### Powered by dry-schema

Both input and response validation use `dry-schema`:
- Consistent API for defining schemas
- Automatic type coercion
- Detailed error messages
- Built-in validation rules

### Filtering Mechanism

dry-schema automatically filters data:
```ruby
# Schema only defines these fields
schema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

# Data has extra fields
data = { name: "John", email: "john@example.com", password: "secret", admin: true }

# Calling schema.call(data).to_h returns:
# { name: "John", email: "john@example.com" }
# Extra fields automatically removed!
```

### Schema Result Detection

When you return a `Dry::Schema::Result` object, the framework automatically detects it and extracts the hash:

```ruby
# Handler returns schema result
api.post '/users' do |input, req, task|
  result = UserOutput.call(user_data)
  [result, 201]  # Returns Dry::Schema::Result
end

# Framework checks:
# 1. Is payload a Dry::Schema::Result? Yes
# 2. Extract: result.to_h
# 3. Send filtered hash to client

# Works with arrays too:
api.post '/users/batch' do |input, req, task|
  results = users.map { |u| UserOutput.call(u) }
  [results, 201]  # Array of Dry::Schema::Result
end

# Framework maps each result to .to_h automatically
```

## Future Enhancements

- OpenAPI/Swagger documentation generation from schemas
- `response_schema_exclude_unset` option (exclude default values)
- `response_schema_include/exclude` options for field filtering
- Response streaming support
- Content negotiation (JSON, XML, etc.)
