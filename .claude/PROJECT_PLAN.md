# Project Overview

A minimal, async-first Ruby web framework inspired by FastAPI. Built on top of Falcon and dry-schema, FunApi provides a simple, performant way to build web APIs in Ruby with a focus on developer experience.

## Philosophy

FunApi aims to bring FastAPI's excellent developer experience to Ruby by providing:

- **Async-first**: Built on Ruby's Async library and Falcon server for high-performance concurrent operations
- **Simple validation**: Using dry-schema for straightforward request validation
- **Minimal magic**: Clear, explicit APIs without heavy DSLs
- **Easy to start**: Get an API up and running in minutes
- **Auto-documentation**: Automatic OpenAPI/Swagger documentation generation

## Current Status (Updated 2024-10-26)

### ✅ Production-Ready Features Implemented:

**Core Framework**
- ✅ Async-first request handling with Async::Task
- ✅ Route definition with path params
- ✅ Request validation (body/query) with array support
- ✅ Response schema validation and filtering
- ✅ FastAPI-style error responses
- ✅ Falcon server integration

**Documentation**
- ✅ OpenAPI/Swagger documentation generation
- ✅ Automatic /docs and /openapi.json endpoints
- ✅ Schema introspection and conversion

**Middleware**
- ✅ Rack-compatible middleware system
- ✅ Built-in middleware (CORS, TrustedHost, RequestLogger, Gzip)
- ✅ FastAPI-style convenience methods (add_cors, add_trusted_host, etc.)
- ✅ Full ecosystem support (rack-attack, rack-cache, etc.)

**Testing**
- ✅ Comprehensive test suite (90 tests, 217 assertions)
- ✅ Router tests
- ✅ Schema validation tests
- ✅ Middleware tests
- ✅ Async operation tests
- ✅ Exception handling tests
- ✅ Fast execution (~220ms)

### 📋 What to Tackle Next

### Immediate Priority (Next Sprint)

1. **Dependency Injection System** - FastAPI's killer feature

• `Depends()` equivalent for Ruby
• Request-scoped dependencies
• Nested dependencies
• Enables clean auth patterns, database connections, shared services

Why first: Core differentiator, enables advanced patterns, critical for FastAPI parity

2. **Background Tasks** - Post-response execution

• Fire-and-forget operations after response sent
• Email sending, logging, cleanup
• Leverages existing async foundation

Why second: Common production need, natural fit with async architecture
• Request-scoped dependencies
• Nested dependencies
• Makes testing clean

Why second: Differentiates FunApi, enables auth patterns, critical for
FastAPI parity

### Secondary Priority (Following Sprints)

3. Background Tasks - Leverage async foundation 4. Lifecycle Hooks -
Startup/shutdown, exception handlers 5. File Uploads - Multipart handling 6.
Path Parameter Types - Type coercion and validation

### Nice to Have

• WebSocket support
• Content negotiation
• TestClient utilities
• Security schemes
