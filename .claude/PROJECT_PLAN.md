# Project Overview

A minimal, async-first Ruby web framework inspired by FastAPI. Built on top of Falcon and dry-schema, FunApi provides a simple, performant way to build web APIs in Ruby with a focus on developer experience.

## Philosophy

FunApi aims to bring FastAPI's excellent developer experience to Ruby by providing:

- **Async-first**: Built on Ruby's Async library and Falcon server for high-performance concurrent operations
- **Simple validation**: Using dry-schema for straightforward request validation
- **Minimal magic**: Clear, explicit APIs without heavy DSLs
- **Easy to start**: Get an API up and running in minutes
- **Auto-documentation**: Automatic OpenAPI/Swagger documentation generation

## Current Status (Updated 2024-10-27)

### ✅ Production-Ready Features Implemented:

**Core Framework**
- ✅ Async-first request handling with Async::Task
- ✅ Route definition with path params
- ✅ Request validation (body/query) with array support
- ✅ Response schema validation and filtering
- ✅ FastAPI-style error responses
- ✅ Falcon server integration

**Dependency Injection** ⭐ NEW
- ✅ Block-based dependencies with `ensure` cleanup
- ✅ Request-scoped caching
- ✅ Nested dependencies with `FunApi::Depends()`
- ✅ Three patterns: simple, tuple, block (Ruby-idiomatic)
- ✅ Automatic resource lifecycle (setup → use → cleanup)
- ✅ FastAPI `Depends()` parity

**Documentation**
- ✅ OpenAPI/Swagger documentation generation
- ✅ Automatic /docs and /openapi.json endpoints
- ✅ Schema introspection and conversion

**Middleware**
- ✅ Rack-compatible middleware system
- ✅ Built-in middleware (CORS, TrustedHost, RequestLogger, Gzip)
- ✅ FastAPI-style convenience methods
- ✅ Full ecosystem support (rack-attack, rack-cache, etc.)

**Testing**
- ✅ Comprehensive test suite (121 tests, 281 assertions)
- ✅ Router, schema, middleware, async, exceptions
- ✅ Dependency injection (31 new tests)
- ✅ Fast execution (~200ms)

### 📋 What to Tackle Next

### Immediate Priority

1. **Background Tasks** - Post-response execution
   - Fire-and-forget after response sent
   - Email, logging, cleanup tasks
   - Leverages async foundation
   - Why: Common production pattern, natural async fit

2. **Lifecycle Hooks** - Startup/shutdown
   - App initialization/cleanup
   - Exception handlers
   - Why: Production deployment needs

### Secondary Priority

3. **Path Parameter Types** - Type coercion/validation
4. **File Uploads** - Multipart handling  
5. **WebSocket Support** - Real-time connections
6. **Global Dependencies** - Apply to all routes
7. **Dependency Overrides** - Testing utilities

### Nice to Have

- Content negotiation (JSON, XML, MessagePack)
- TestClient utilities
- Security schemes (OAuth2, JWT helpers)
- Response streaming
