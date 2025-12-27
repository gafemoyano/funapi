# TodoMVC - PostgreSQL + Vanilla JS Edition

A classic [TodoMVC](http://todomvc.com) implementation showcasing FunApi with async PostgreSQL and pure vanilla JavaScript (no HTMX, no frameworks).

## Architecture

This example demonstrates a **pure JSON API architecture**:

- **Backend**: FunApi with async PostgreSQL (`db-postgres`)
- **Frontend**: Vanilla JavaScript SPA (Single Page Application)
- **Communication**: JSON API (no server-side rendering)
- **Database**: PostgreSQL with async queries

## Features

### Backend (FunApi + PostgreSQL)
- ✅ Pure JSON API endpoints
- ✅ Async PostgreSQL queries with `db-postgres`
- ✅ Request validation with FunApi schemas
- ✅ CRUD operations on todos table
- ✅ Filter support (All / Active / Completed)
- ✅ Bulk operations (toggle all, clear completed)
- ✅ CORS enabled for API access

### Frontend (Vanilla JavaScript)
- ✅ Zero frameworks (pure JavaScript)
- ✅ Client-side routing with hash navigation
- ✅ Fetch API for HTTP requests
- ✅ Double-click to edit todos
- ✅ Keyboard shortcuts (Enter to save, Escape to cancel)
- ✅ Classic TodoMVC styling
- ✅ Reactive UI updates

## Tech Stack

**Backend:**
- FunApi (async-first Ruby framework)
- db-postgres (async PostgreSQL adapter)
- Falcon (async HTTP server)

**Frontend:**
- Vanilla JavaScript (ES6+)
- Fetch API
- Modern CSS
- Hash-based routing

**Database:**
- PostgreSQL 12+

## Prerequisites

- Ruby 3.2 or higher
- PostgreSQL 12+ running locally or remotely
- Bundler gem

## Setup

### 1. Install Dependencies

```bash
cd examples/apps/todo-app-postgres
bundle install
```

### 2. Configure PostgreSQL

Set environment variables for your PostgreSQL connection (or use defaults):

```bash
# Optional - defaults shown below
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=todos
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
```

**Defaults:**
- Host: `localhost`
- Port: `5432`
- Database: `todos`
- User: `postgres`
- Password: `postgres`

### 3. Create Database

```bash
# Using psql
createdb todos

# Or via psql
psql -U postgres -c "CREATE DATABASE todos;"
```

The app will automatically create the `todos` table on startup.

### 4. Run the Application

```bash
ruby app.rb
```

### 5. Open in Browser

```
http://localhost:3000
```

## Database Schema

```sql
CREATE TABLE todos (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

## API Endpoints

### Todos

```bash
# Get all todos (with optional filter)
GET /api/todos?filter=all|active|completed

# Create a new todo
POST /api/todos
Body: { "title": "Buy milk" }

# Get a single todo
GET /api/todos/:id

# Update a todo
PATCH /api/todos/:id
Body: { "title": "New title" } or { "completed": true }

# Delete a todo
DELETE /api/todos/:id

# Clear all completed todos
DELETE /api/todos/completed/all

# Toggle all todos
POST /api/todos/toggle-all
Body: { "completed": true }
```

### Response Format

**Get Todos:**
```json
{
  "todos": [
    {
      "id": 1,
      "title": "Buy milk",
      "completed": false,
      "created_at": "2024-12-27T10:00:00Z",
      "updated_at": "2024-12-27T10:00:00Z"
    }
  ],
  "stats": {
    "active_count": 5,
    "completed_count": 3,
    "total_count": 8
  }
}
```

## Usage

### Creating Todos
- Type in the input field
- Press Enter

### Editing Todos
- **Double-click** on a todo to edit
- **Enter** to save
- **Escape** to cancel
- Empty text prompts for deletion

### Toggling Completion
- Click the checkbox
- Click "Mark all as complete" to toggle all

### Filtering
- Click **All** / **Active** / **Completed**
- Uses hash routing (`#/active`, `#/completed`)

### Deleting
- Hover and click the **×** button
- Click **Clear completed** to remove all completed

## Project Structure

```
todo-app-postgres/
├── app.rb              # FunApi JSON API
├── database.rb         # db-postgres setup + TodoRepository
├── index.html          # SPA entry point
├── Gemfile             # Dependencies
├── README.md           # This file
├── public/
│   ├── app.js          # Vanilla JS client
│   └── style.css       # TodoMVC styling
```

## FunApi Features Demonstrated

1. **Async PostgreSQL Integration** - `db-postgres` with connection pooling
2. **JSON API Endpoints** - Pure REST API (no templates)
3. **Request Validation** - Type-safe schemas
4. **CORS Support** - `api.add_cors()`
5. **Static File Serving** - `Rack::Static`
6. **Error Handling** - `HTTPException` for 404s
7. **Path Parameters** - `/api/todos/:id`
8. **Query Parameters** - Filter support
9. **Multiple HTTP Methods** - GET, POST, PATCH, DELETE

## Differences from todo-app (SQLite + HTMX)

| Feature | todo-app | todo-app-postgres |
|---------|----------|-------------------|
| Database | SQLite + Sequel | PostgreSQL + db-postgres |
| Frontend | HTMX + minimal JS | Pure Vanilla JS SPA |
| Rendering | Server-side ERB | Client-side JS |
| API | Hybrid HTML/JSON | Pure JSON |
| Interactivity | HTMX attributes | Fetch API |
| Routing | Server-side | Hash-based client routing |

## Testing Async Operations

This example validates:
- ✅ db-postgres works in FunApi's async context
- ✅ Connection pooling handles concurrent requests
- ✅ No Fiber scheduling conflicts
- ✅ Parameterized queries prevent SQL injection
- ✅ Session management is correct

Test concurrent operations by:
1. Opening multiple browser tabs
2. Creating/editing todos simultaneously
3. Checking PostgreSQL connection logs

## PostgreSQL Connection Monitoring

```bash
# Check active connections
psql -U postgres -d todos -c "SELECT COUNT(*) FROM pg_stat_activity WHERE datname='todos';"

# View current queries
psql -U postgres -d todos -c "SELECT pid, query FROM pg_stat_activity WHERE datname='todos';"
```

## Docker Setup (Optional)

Run PostgreSQL in Docker:

```bash
docker run --name postgres-todos \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=todos \
  -p 5432:5432 \
  -d postgres:14-alpine
```

Then run the app:

```bash
ruby app.rb
```

## Troubleshooting

### Connection Failed

```
Database initialization failed: connection refused
```

**Solutions:**
- Ensure PostgreSQL is running: `pg_ctl status`
- Check connection settings in environment variables
- Verify database exists: `psql -l | grep todos`

### Table Creation Error

```
Database initialization failed: permission denied
```

**Solutions:**
- Ensure user has CREATE TABLE permissions
- Try running as postgres superuser
- Check `POSTGRES_USER` has sufficient privileges

### Port Already in Use

```
Address already in use - bind(2)
```

**Solution:**
- Kill process on port 3000: `lsof -ti:3000 | xargs kill`
- Or change port in `app.rb`: `FunApi::Server::Falcon.start(app, port: 3001)`

## Development

### Resetting Database

```bash
psql -U postgres -c "DROP DATABASE todos;"
psql -U postgres -c "CREATE DATABASE todos;"
ruby app.rb  # Recreates table
```

### Viewing Logs

```bash
# PostgreSQL logs (location varies by OS)
tail -f /usr/local/var/log/postgresql@14.log  # macOS Homebrew
tail -f /var/log/postgresql/postgresql-14-main.log  # Ubuntu
```

## Performance Notes

- **db-postgres** uses async I/O for non-blocking database queries
- Connection pooling is handled automatically by `DB::Client`
- Each request gets its own session for isolation
- Sessions are closed after use to prevent leaks

## License

This example is part of the FunApi project and follows the same license.

## Credits

- Based on the [TodoMVC](http://todomvc.com) project
- Built with [FunApi](https://github.com/gafemoyano/funapi)
- Uses [db-postgres](https://github.com/socketry/db-postgres) for async PostgreSQL
- Styling inspired by [TodoMVC CSS](https://github.com/tastejs/todomvc-app-css)
