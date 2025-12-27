# FunApi Example Applications

This directory contains full-featured example applications built with FunApi to demonstrate real-world usage patterns.

## Available Examples

### 📝 [todo-app](./todo-app/)

A complete TodoMVC implementation showcasing:

- **Full CRUD operations** with SQLite + Sequel
- **Async database queries** testing FunApi's async philosophy
- **Template rendering** with ERB layouts and partials
- **Request validation** with FunApi schemas
- **HTMX interactivity** for reactive updates without heavy JavaScript
- **Classic TodoMVC styling** with modern CSS
- **Keyboard shortcuts** (Enter to save, Escape to cancel)
- **Double-click to edit** inline editing

**Tech Stack:** FunApi, Sequel, SQLite3, HTMX, Vanilla JS, Modern CSS

**How to run:**
```bash
cd todo-app
bundle install
ruby app.rb
# Open http://localhost:3000
```

### 🐘 [todo-app-postgres](./todo-app-postgres/)

The same TodoMVC app but with async PostgreSQL and vanilla JavaScript:

- **Pure JSON API** - No server-side rendering
- **Async PostgreSQL** with db-postgres
- **Vanilla JavaScript SPA** - No HTMX, pure client-side
- **Client-side routing** with hash navigation
- **Fetch API** for HTTP requests
- **Same TodoMVC features** - All CRUD operations
- **Classic styling** - Identical UI/UX

**Tech Stack:** FunApi, db-postgres, PostgreSQL, Vanilla JS (no frameworks)

**How to run:**
```bash
# Ensure PostgreSQL is running
createdb todos

cd todo-app-postgres
bundle install
ruby app.rb
# Open http://localhost:3000
```

## Coming Soon

- **blog-app** - Multi-user blog with authentication and markdown
- **api-server** - Pure JSON API with authentication
- **realtime-chat** - WebSocket-based chat application
- **file-upload** - File upload and processing example

## Purpose

These examples serve multiple purposes:

1. **Learning** - See how FunApi works in complete applications
2. **Testing** - Validate async compatibility with various gems (Sequel, etc.)
3. **Reference** - Copy patterns for your own projects
4. **Dogfooding** - Use FunApi to build real apps and find issues

## Contributing

To add a new example:

1. Create a new directory under `examples/apps/`
2. Include a comprehensive README with setup instructions
3. Demonstrate unique FunApi features or integration patterns
4. Keep dependencies minimal
5. Follow the existing structure pattern

## License

All examples are part of the FunApi project and follow the same license.
