---
title: Errors Reference
---

# Errors Reference

Every error FunApi emits is JSON with a single top-level `detail` key, matching
FastAPI's convention. This page is the complete contract: the exact shape an API
consumer — or a coding agent iterating against your API — can encounter for each
status code. If you are handling errors programmatically, key off `detail`.

## The contract in one sentence

> All framework error responses are `application/json` with a top-level `detail`.
> `detail` is either a **string** (a human message) or an **array of field
> errors** (validation). Never assume any other top-level key.

## 400 — Bad Request

Returned when the request body cannot be parsed (for example, malformed JSON on a
route that expects `application/json`). `detail` is an array of field errors:

```json
{
  "detail": [
    {
      "loc": ["body"],
      "msg": "Invalid JSON: unexpected token at 'not json'",
      "type": "json_invalid"
    }
  ]
}
```

You can also raise it yourself for domain-level bad input:

```ruby
raise FunApi::HTTPException.new(status_code: 400, detail: "Invalid input")
```

which produces a string `detail`:

```json
{ "detail": "Invalid input" }
```

## 404 — Not Found

Returned when no route matches the request method and path. The body is uniform
with every other error (there is no `error` key):

```json
{ "detail": "Not Found" }
```

Raising `HTTPException` with `status_code: 404` and a custom `detail` (for a
missing record, say) produces the same shape with your message.

## 422 — Unprocessable Entity (validation)

Raised automatically when request data fails a `path:`, `query:`, `body:`, or
model validation. `detail` is an **array** of field errors. Each entry has
`loc` (the path to the offending field), `msg`, and `type`:

```json
{
  "detail": [
    {
      "loc": ["name"],
      "msg": "is missing",
      "type": "value_error"
    },
    {
      "loc": ["quantity"],
      "msg": "must be greater than or equal to 0",
      "type": "value_error"
    }
  ]
}
```

`loc` is an array of strings so nested fields are addressable
(`["address", "zip"]`). This is the one error whose `detail` is not a string —
handle both cases when parsing.

## 426 — Upgrade Required

Returned when a WebSocket route (`api.websocket "..."`) is hit with a plain HTTP
request that does not carry the WebSocket upgrade headers. This response is
`text/plain` (it is a protocol-level signal, not an API payload) and carries
`Connection: upgrade` and `Upgrade: websocket` headers:

```
Upgrade Required
```

## 500 — Internal Server Error

Any `StandardError` that is not an `HTTPException` and has no registered handler
becomes a 500. **In production the body is always the generic message** — no
class, no message, no backtrace ever leaks:

```json
{ "detail": "Internal Server Error" }
```

### Development variants

When `FUNAPI_ENV` (or `RACK_ENV`) is `development`, 500s are enriched to speed up
the iterate-fix loop. There are two variants, chosen by the request `Accept`
header:

**JSON clients** (`Accept: application/json`) get a structured `detail` object
with the error class, message, and a trimmed backtrace:

```json
{
  "detail": {
    "error": "RuntimeError",
    "message": "something broke",
    "backtrace": ["app.rb:12:in ...", "..."]
  }
}
```

**Browsers** (`Accept` prefers `text/html`) get a minimal HTML traceback page
(`text/html; charset=utf-8`) with no external assets. Both development variants
are disabled in production.

## Raising errors yourself

Use `HTTPException` for any status code. `detail` may be a string or a structured
value (array/hash) and is serialized as-is under the `detail` key:

```ruby
raise FunApi::HTTPException.new(status_code: 409, detail: "Already exists")
raise FunApi::HTTPException.new(
  status_code: 401,
  detail: "Token expired",
  headers: { "WWW-Authenticate" => "Bearer" }
)
```

For validation-shaped errors, `ValidationError` builds the 422 array for you:

```ruby
raise FunApi::ValidationError.new(
  errors: [{ path: [:email], text: "is invalid" }]
)
```

## Custom handlers override the shape

`api.exception_handler(SomeError) { |error, req| [payload, status] }` lets you
return any payload for a given exception class. If you register a handler, the
`payload` you return is serialized verbatim — you own the shape for that error,
so keep it `detail`-based if you want to stay consistent with the framework
contract. See [Error Handling](/docs/patterns/error-handling) for the full
handler API.

## Summary table

| Status | When | `detail` type | Content-Type |
| --- | --- | --- | --- |
| 400 | Unparseable body / bad input | array or string | `application/json` |
| 404 | No route matched | string | `application/json` |
| 422 | Validation failed | array of field errors | `application/json` |
| 426 | Non-upgrade request to a WebSocket route | (plain text body) | `text/plain` |
| 500 (prod) | Unhandled error | string (`"Internal Server Error"`) | `application/json` |
| 500 (dev, JSON) | Unhandled error | object (`error`/`message`/`backtrace`) | `application/json` |
| 500 (dev, browser) | Unhandled error | HTML traceback page | `text/html` |
