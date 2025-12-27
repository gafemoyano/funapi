# Conduit - RealWorld Full-Stack Example

A complete full-stack implementation of the [RealWorld](https://github.com/gothinkster/realworld) "Conduit" specification - a Medium.com clone built with FunApi (backend) and React 19 (frontend).

**"The mother of all demo apps"** - Showcasing a production-ready full-stack application with authentication, articles, comments, and social features.

## Overview

This is a **complete full-stack application** with both backend API and React frontend that adheres to the [RealWorld spec](https://realworld-docs.netlify.app/).

### Key Features

- ✅ **User Authentication** - JWT-based auth with registration and login
- ✅ **User Profiles** - View profiles and follow/unfollow users
- ✅ **Articles** - Full CRUD operations with slugs
- ✅ **Comments** - Threaded comments on articles
- ✅ **Favorites** - Favorite articles
- ✅ **Tags** - Tag-based article categorization
- ✅ **Feed** - Personalized article feed from followed users
- ✅ **Pagination** - Limit/offset for article lists
- ✅ **Filtering** - Filter by tag, author, favorited by user

## Tech Stack

**Backend:**
- **FunApi** - Async-first Ruby web framework
- **Sequel** - SQL database toolkit and ORM
- **PostgreSQL** - Relational database
- **JWT** - JSON Web Token authentication
- **BCrypt** - Secure password hashing

**Frontend:**
- **React 19** - Latest React with hooks
- **Vite** - Modern build tool and dev server
- **Tailwind CSS** - Utility-first CSS framework
- **Marked** - Markdown parser for article rendering
- **No Router** - Simple state-based navigation (no React Router)

## Prerequisites

- Ruby 3.2 or higher
- PostgreSQL 12+
- Node.js 18+ and npm
- Bundler gem

## Installation

### 1. Clone and Navigate

```bash
cd examples/apps/conduit-api
```

### 2. Install Dependencies

```bash
bundle install
```

### 3. Configure Database

Set environment variables (or use defaults):

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=conduit
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
```

### 4. Create Database

```bash
createdb conduit
```

Or via psql:
```bash
psql -U postgres -c "CREATE DATABASE conduit;"
```

### 5. Run Migrations

```bash
ruby db/migrate.rb
```

### 6. Configure JWT Secret (Production)

```bash
export JWT_SECRET=your-super-secret-key
```

**Note:** In development, a default key is used. Change this in production!

### 7. Install Frontend Dependencies

```bash
cd frontend
npm install
cd ..
```

### 8. Build Frontend

For production, build the React frontend:

```bash
cd frontend
npm run build
cd ..
```

This creates a production build in `frontend/dist/` that will be served by the backend.

### 9. Start the Server

```bash
ruby app.rb
```

Server will start on `http://localhost:3000` and serve both the API and the React frontend.

## API Documentation

### Authentication

**Register**
```bash
POST /api/users
{
  "user": {
    "username": "johndoe",
    "email": "john@example.com",
    "password": "secret123"
  }
}
```

**Login**
```bash
POST /api/users/login
{
  "user": {
    "email": "john@example.com",
    "password": "secret123"
  }
}
```

**Get Current User** (requires auth)
```bash
GET /api/user
Authorization: Token jwt.token.here
```

**Update User** (requires auth)
```bash
PUT /api/user
Authorization: Token jwt.token.here
{
  "user": {
    "email": "newemail@example.com",
    "bio": "I like Ruby",
    "image": "https://example.com/avatar.jpg"
  }
}
```

### Profiles

**Get Profile**
```bash
GET /api/profiles/:username
```

**Follow User** (requires auth)
```bash
POST /api/profiles/:username/follow
Authorization: Token jwt.token.here
```

**Unfollow User** (requires auth)
```bash
DELETE /api/profiles/:username/follow
Authorization: Token jwt.token.here
```

### Articles

**List Articles**
```bash
GET /api/articles?tag=ruby&author=johndoe&favorited=janedoe&limit=20&offset=0
```

**Get User Feed** (requires auth)
```bash
GET /api/articles/feed
Authorization: Token jwt.token.here
```

**Get Article**
```bash
GET /api/articles/:slug
```

**Create Article** (requires auth)
```bash
POST /api/articles
Authorization: Token jwt.token.here
{
  "article": {
    "title": "How to build APIs",
    "description": "A guide to building APIs with FunApi",
    "body": "# Introduction\n\nLet's build an API...",
    "tagList": ["ruby", "funapi", "api"]
  }
}
```

**Update Article** (requires auth)
```bash
PUT /api/articles/:slug
Authorization: Token jwt.token.here
{
  "article": {
    "title": "Updated title"
  }
}
```

**Delete Article** (requires auth)
```bash
DELETE /api/articles/:slug
Authorization: Token jwt.token.here
```

**Favorite Article** (requires auth)
```bash
POST /api/articles/:slug/favorite
Authorization: Token jwt.token.here
```

**Unfavorite Article** (requires auth)
```bash
DELETE /api/articles/:slug/favorite
Authorization: Token jwt.token.here
```

### Comments

**Get Comments**
```bash
GET /api/articles/:slug/comments
```

**Create Comment** (requires auth)
```bash
POST /api/articles/:slug/comments
Authorization: Token jwt.token.here
{
  "comment": {
    "body": "Great article!"
  }
}
```

**Delete Comment** (requires auth)
```bash
DELETE /api/articles/:slug/comments/:id
Authorization: Token jwt.token.here
```

### Tags

**Get All Tags**
```bash
GET /api/tags
```

## Project Structure

```
conduit-api/
├── app.rb                      # Main application entry point
├── Gemfile                     # Ruby dependencies
├── config/
│   └── database.rb             # Sequel + PostgreSQL config
├── db/
│   ├── migrate.rb              # Migration runner
│   └── migrations/             # Database migrations
│       ├── 001_create_users.rb
│       ├── 002_create_articles.rb
│       ├── 003_create_comments.rb
│       ├── 004_create_tags.rb
│       ├── 005_create_article_tags.rb
│       └── 006_create_follows_and_favorites.rb
├── models/
│   ├── user.rb                 # User model
│   ├── article.rb              # Article model
│   ├── comment.rb              # Comment model
│   └── tag.rb                  # Tag model
├── services/
│   └── auth.rb                 # JWT authentication
├── routes/
│   ├── users.rb                # User/auth routes
│   ├── profiles.rb             # Profile routes
│   ├── articles.rb             # Article routes
│   ├── comments.rb             # Comment routes
│   └── tags.rb                 # Tag routes
├── schemas/
│   ├── user_schemas.rb         # User validation
│   ├── article_schemas.rb      # Article validation
│   └── comment_schemas.rb      # Comment validation
└── frontend/                   # React application
    ├── package.json            # Frontend dependencies
    ├── vite.config.js          # Vite configuration
    ├── tailwind.config.js      # Tailwind CSS config
    ├── index.html              # HTML entry point
    ├── src/
    │   ├── main.jsx            # React entry point
    │   ├── App.jsx             # Main app component
    │   ├── index.css           # Global styles
    │   ├── components/         # React components
    │   │   ├── Header.jsx
    │   │   ├── Home.jsx
    │   │   ├── Login.jsx
    │   │   ├── Register.jsx
    │   │   ├── ArticleDetail.jsx
    │   │   ├── ArticlePreview.jsx
    │   │   ├── Editor.jsx
    │   │   ├── Profile.jsx
    │   │   └── Settings.jsx
    │   ├── hooks/
    │   │   └── useAuth.js      # Auth context hook
    │   └── services/
    │       └── api.js          # API client
    └── dist/                   # Built frontend (after npm run build)
```

## Database Schema

### Users
- `id` (primary key)
- `email` (unique)
- `username` (unique)
- `password_hash`
- `bio`
- `image`
- `created_at`, `updated_at`

### Articles
- `id` (primary key)
- `slug` (unique)
- `title`
- `description`
- `body`
- `author_id` (foreign key → users)
- `created_at`, `updated_at`

### Comments
- `id` (primary key)
- `body`
- `article_id` (foreign key → articles)
- `author_id` (foreign key → users)
- `created_at`, `updated_at`

### Tags
- `id` (primary key)
- `name` (unique)

### Article_Tags (Join Table)
- `article_id` (foreign key)
- `tag_id` (foreign key)

### Favorites (Join Table)
- `user_id` (foreign key)
- `article_id` (foreign key)

### Follows (Join Table)
- `follower_id` (foreign key → users)
- `followee_id` (foreign key → users)

## Running the Application

### Development Mode (with Hot Reload)

For development, run the backend and frontend separately:

**Terminal 1 - Backend:**
```bash
ruby app.rb
```

**Terminal 2 - Frontend (with hot reload):**
```bash
cd frontend
npm run dev
```

The frontend dev server runs on `http://localhost:5173` and proxies API requests to the backend at `http://localhost:3000`.

Visit `http://localhost:5173` to use the application with hot reload.

### Production Mode

In production, the backend serves the built frontend:

1. Build the frontend: `cd frontend && npm run build`
2. Start the backend: `ruby app.rb`
3. Visit `http://localhost:3000`

The backend automatically serves the React app from `frontend/dist/` for all non-API routes.

## Testing with Other RealWorld Frontends

You can also use any RealWorld frontend with this backend:

```bash
# Clone any RealWorld frontend
git clone https://github.com/gothinkster/react-redux-realworld-example-app.git
cd react-redux-realworld-example-app

# Update API URL to point to your backend
# Edit src/agent.js and set API_ROOT to 'http://localhost:3000/api'

# Install and run
npm install
npm start
```

## Frontend Architecture

The React frontend uses a modern, hooks-based architecture without a router library:

### Key Features

- **No Router Library**: Uses simple state-based navigation instead of React Router
- **useAuth Hook**: Provides authentication context throughout the app
- **API Service Layer**: Centralized API client in `services/api.js`
- **Functional Components**: All components use hooks
- **Tailwind CSS**: Utility-first styling
- **Markdown Support**: Marked library for rendering article content

### Main Files

- `src/App.jsx` - Main app component with navigation logic
- `src/hooks/useAuth.js` - Authentication context and methods (login, register, logout, updateUser)
- `src/services/api.js` - API client with all endpoint methods
- `src/components/Header.jsx` - Navigation header with auth state
- `src/components/Home.jsx` - Home page with article feed and tags sidebar
- `src/components/ArticleDetail.jsx` - Article view with markdown rendering and comments
- `src/components/Editor.jsx` - Article create/edit form
- `src/components/Profile.jsx` - User profile with articles and follow/unfollow
- `src/components/Settings.jsx` - User settings and logout

### Navigation Pattern

Instead of React Router, the app uses simple state-based navigation:

```javascript
// In App.jsx
const [currentPage, setCurrentPage] = useState('home');
const [selectedArticle, setSelectedArticle] = useState(null);

const navigate = (page, data = null) => {
  setCurrentPage(page);
  if (page === 'article') setSelectedArticle(data);
};

// Components receive onNavigate callback
<Home onNavigate={navigate} />
```

This keeps the frontend simple and lightweight while still providing full navigation capabilities.

### API Integration

The API service handles all backend communication:

```javascript
// From services/api.js
const token = getToken(); // From localStorage
const headers = { 'Content-Type': 'application/json' };
if (token) headers['Authorization'] = `Token ${token}`;

// All endpoints are organized by resource
export const auth = { register, login, getCurrentUser, updateUser };
export const articles = { list, feed, get, create, update, delete, favorite, unfavorite };
export const profiles = { get, follow, unfollow };
export const comments = { list, create, delete };
export const tags = { list };
```

## Backend Features Demonstrated

1. **Modular Architecture** - Separate files for routes, models, services
2. **Request Validation** - FunApi schemas for type safety
3. **JWT Authentication** - Custom auth service with middleware
4. **Sequel ORM** - Models with associations and validations
5. **Database Migrations** - Sequel migrations for schema management
6. **CORS Support** - Enable frontend integration
7. **Error Handling** - Proper HTTP exceptions with status codes
8. **Path Parameters** - Dynamic routes (`:slug`, `:username`)
9. **Query Parameters** - Filtering and pagination
10. **Async Operations** - All database queries in async context
11. **JSON API** - RESTful API following RealWorld spec
12. **Password Security** - BCrypt hashing
13. **Token Auth** - JWT generation and verification
14. **Static File Serving** - Serves built React frontend from dist/

## Development

### Reset Database

```bash
dropdb conduit
createdb conduit
ruby db/migrate.rb
```

### Check Database

```bash
psql -U postgres -d conduit
\dt  # List tables
\d users  # Describe users table
```

### Create Test Data

```ruby
# In irb or pry
require_relative "app"

# Create a user
user = User.create_with_password(
  email: "test@example.com",
  username: "testuser",
  password: "password123"
)

# Create an article
article = Article.create_with_slug(
  title: "Test Article",
  description: "This is a test",
  body: "Article content here",
  author_id: user.id,
  tag_list: ["test", "ruby"]
)
```

## Troubleshooting

### Database Connection Error

```
PG::ConnectionBad: could not connect to server
```

**Solution:**
- Ensure PostgreSQL is running: `pg_ctl status`
- Check connection settings in environment variables
- Verify database exists: `psql -l | grep conduit`

### JWT Token Invalid

```
401 Unauthorized
```

**Solution:**
- Ensure `Authorization` header format is: `Token jwt.token.here`
- Check JWT secret is consistent
- Verify token hasn't expired (24 hour expiration)

### Migration Errors

```
Sequel::Migrator::Error: duplicate column name
```

**Solution:**
- Reset database and re-run migrations
- Check migration files for conflicts

## Security Notes

- 🔒 Passwords are hashed with BCrypt before storage
- 🔑 JWT tokens expire after 24 hours
- 🛡️ SQL injection prevention via parameterized queries
- 🚫 Authorization checks on protected endpoints
- 🔐 Change `JWT_SECRET` in production!

## Performance

- ✅ Database connection pooling (max 10 connections)
- ✅ Indexed columns for fast queries (email, username, slug)
- ✅ Async request handling with Falcon server
- ✅ Efficient SQL queries with Sequel

## License

This example is part of the FunApi project and follows the same license.

## Credits

- Based on the [RealWorld](https://github.com/gothinkster/realworld) specification
- Built with [FunApi](https://github.com/gafemoyano/funapi)
- Inspired by [FastAPI's full-stack template](https://github.com/fastapi/full-stack-fastapi-template)
