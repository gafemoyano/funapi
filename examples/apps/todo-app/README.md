# TodoMVC - FunApi Edition

A classic [TodoMVC](http://todomvc.com) implementation built with FunApi to demonstrate real-world usage of the framework.

## Features

- ✅ **Full CRUD operations** - Create, read, update, and delete todos
- ✅ **Toggle completion** - Mark todos as complete/incomplete
- ✅ **Edit inline** - Double-click to edit todo text
- ✅ **Filter todos** - View All, Active, or Completed
- ✅ **Clear completed** - Remove all completed todos at once
- ✅ **Toggle all** - Mark all todos as complete/incomplete
- ✅ **Persistent storage** - SQLite database with Sequel ORM
- ✅ **Async operations** - Test FunApi's async-first philosophy with real database queries
- ✅ **Zero-JavaScript interactivity** - HTMX handles most interactions
- ✅ **Keyboard shortcuts** - Enter to save, Escape to cancel

## Tech Stack

### Backend
- **FunApi** - Async-first Ruby web framework
- **Sequel** - Ruby database toolkit
- **SQLite3** - Lightweight SQL database
- **Falcon** - High-performance async HTTP server

### Frontend
- **HTML5** - Semantic markup
- **Modern CSS** - TodoMVC classic styling with CSS variables
- **HTMX** - Reactive HTML updates without heavy JavaScript
- **Vanilla JavaScript** - Minimal scripting for editing and keyboard shortcuts

## Prerequisites

- Ruby 3.2 or higher
- Bundler gem

## Installation

1. **Navigate to the todo-app directory:**
   ```bash
   cd examples/apps/todo-app
   ```

2. **Install dependencies:**
   ```bash
   bundle install
   ```

3. **Run the application:**
   ```bash
   ruby app.rb
   ```

4. **Open in your browser:**
   ```
   http://localhost:3000
   ```

## Usage

### Creating Todos
- Type in the input field at the top
- Press Enter or click "Add"

### Editing Todos
- **Double-click** on a todo to edit
- **Enter** to save
- **Escape** to cancel
- Clearing the text will prompt to delete

### Toggling Completion
- Click the checkbox to toggle a todo's completion status
- Click "Mark all as complete" to toggle all todos

### Filtering
- Click **All** to show all todos
- Click **Active** to show only incomplete todos
- Click **Completed** to show only completed todos

### Deleting
- Hover over a todo and click the **×** button
- Click **Clear completed** to remove all completed todos

## API Endpoints

The app also exposes a JSON API for programmatic access:

```bash
# Get all todos as JSON
curl http://localhost:3000/api/todos

# Create a new todo
curl -X POST http://localhost:3000/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy milk"}'

# Update a todo
curl -X PATCH http://localhost:3000/todos/1 \
  -H "Content-Type: application/json" \
  -d '{"completed": true}'

# Delete a todo
curl -X DELETE http://localhost:3000/todos/1
```

## Architecture

### Database Layer (`database.rb`)
- Sequel ORM with SQLite backend
- `TodoRepository` module for data access operations
- Async-safe database queries

### Application Layer (`app.rb`)
- FunApi routes with request validation
- Schema definitions for type safety
- Template rendering with ERB
- HTMX-friendly partial responses

### Presentation Layer (`templates/`)
- Layout with classic TodoMVC styling
- Partials for reusable components
- HTMX attributes for reactive updates

### Static Assets (`public/`)
- **style.css** - TodoMVC-compliant styling
- **app.js** - Editing logic and keyboard shortcuts

## FunApi Features Demonstrated

1. **Request Validation** - `TodoCreateSchema`, `TodoUpdateSchema`
2. **Query Parameters** - Filter support with `FilterQuerySchema`
3. **Template Rendering** - ERB templates with layouts and partials
4. **Async Operations** - Database queries in async context
5. **Static File Serving** - Rack::Static for CSS/JS
6. **HTTP Methods** - GET, POST, PATCH, DELETE
7. **Error Handling** - 404 responses with `HTTPException`
8. **Path Parameters** - `/todos/:id` routes
9. **Partial Responses** - HTMX-compatible HTML fragments
10. **JSON API** - Dual HTML/JSON endpoints

## Testing Async + Sequel

This example validates that:
- Sequel works correctly in FunApi's async context
- Database connections are managed properly
- No Fiber scheduling conflicts occur
- Concurrent requests work as expected

Try opening multiple browser tabs and interacting simultaneously to test async behavior.

## Project Structure

```
todo-app/
├── app.rb              # Main FunApi application
├── database.rb         # Sequel setup and TodoRepository
├── Gemfile             # Dependencies
├── README.md           # This file
├── todo.db             # SQLite database (auto-created)
├── public/
│   ├── style.css       # TodoMVC styling
│   └── app.js          # Editing & keyboard shortcuts
└── templates/
    ├── layout.html.erb # Main HTML layout
    ├── index.html.erb  # Todo list page
    └── _todo.html.erb  # Todo item partial
```

## Development

### Resetting the Database
```bash
rm todo.db
ruby app.rb  # Database will be recreated automatically
```

### Adding Features
Some ideas for extending this example:
- Add due dates to todos
- Implement todo categories/tags
- Add user authentication
- Implement todo search
- Add bulk operations (delete all, archive completed)
- Export/import todos as JSON

## License

This example is part of the FunApi project and follows the same license.

## Credits

- Based on the [TodoMVC](http://todomvc.com) project
- Built with [FunApi](https://github.com/gafemoyano/funapi)
- Styling inspired by [TodoMVC CSS](https://github.com/tastejs/todomvc-app-css)
