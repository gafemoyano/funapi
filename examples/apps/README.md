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

### 🌐 [conduit-api](./conduit-api/)

Full RealWorld "Conduit" API - A Medium.com clone following the official RealWorld spec:

- **Complete RealWorld API** - All endpoints implemented
- **JWT Authentication** - Secure token-based auth
- **User Profiles** - Follow/unfollow users
- **Articles** - Full CRUD with slugs, tags, favorites
- **Comments** - Threaded discussions
- **Feed** - Personalized article feed
- **Modular Architecture** - Organized routes, models, services
- **Production-Ready** - Password hashing, validation, error handling

**Tech Stack:** FunApi, Sequel, PostgreSQL, JWT, BCrypt

**How to run:**
```bash
# Create database
createdb conduit

cd conduit-api
bundle install
ruby db/migrate.rb
ruby app.rb

# Use with any RealWorld frontend!
```

**Frontend Integration:**
Works with any [RealWorld frontend](https://codebase.show/projects/realworld) - React, Vue, Angular, etc.

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
