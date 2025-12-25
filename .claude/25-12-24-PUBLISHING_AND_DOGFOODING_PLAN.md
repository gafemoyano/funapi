# Publishing and Dogfooding Plan

## Date: 2024-12-24

## Overview

This document outlines the strategy for publishing FunApi v0.1 and dogfooding it by building a documentation site with the framework itself.

## Current State

### Completed Features
- Async-first request handling with Falcon
- Route definition with path parameters
- Request validation (body/query) with array support
- Response schema validation and filtering
- FastAPI-style error responses
- OpenAPI/Swagger documentation generation
- Middleware support (Rack-compatible + built-ins)
- Dependency injection with cleanup
- Background tasks (post-response execution)
- Template rendering (ERB with layouts and partials)
- Lifecycle hooks (startup/shutdown)

### Integration Testing
- db-postgres integration verified (7 tests passing)
- Works with testcontainers or existing PostgreSQL
- Concurrent queries work correctly
- Lifecycle hooks integrate with DB connections

### Known Limitations
- Background tasks + db-postgres may have fiber conflicts (needs investigation)
- Path parameter type validation not yet implemented
- WebSocket support pending

## Publishing Strategy

### Option A: Publish to RubyGems First (Recommended)
**Pros:**
- Standard gem installation works immediately
- Version tagging and releases tracked
- Easy for users to try

**Cons:**
- Commits to public API
- Need proper gemspec metadata

**Steps:**
1. Update gemspec with proper metadata (homepage, source_code_uri, etc.)
2. Create GitHub repository (if not exists)
3. Run `gem build fun_api.gemspec`
4. Run `gem push fun_api-0.1.0.gem`
5. Tag release on GitHub

### Option B: Git-based Installation
**Pros:**
- No commitment to RubyGems
- Can iterate quickly
- Private until ready

**Cons:**
- Requires git path in Gemfile
- Less discoverable

**Usage:**
```ruby
gem 'fun_api', git: 'https://github.com/user/fun_api', branch: 'main'
```

### Recommendation
Start with **Option B** for dogfooding, then publish to RubyGems once the docs site is working.

## Gemspec Updates Required

```ruby
# fun_api.gemspec updates needed:
spec.homepage = "https://github.com/gafemoyano/fun_api"
spec.metadata["homepage_uri"] = spec.homepage
spec.metadata["source_code_uri"] = "https://github.com/gafemoyano/fun_api"
spec.metadata["changelog_uri"] = "https://github.com/gafemoyano/fun_api/blob/main/CHANGELOG.md"

# Remove the allowed_push_host restriction for public gem
spec.metadata.delete("allowed_push_host")
```

## Dogfooding: Documentation Site

### Concept
Build the FunApi documentation site using FunApi itself, demonstrating:
- HTMX-powered interactive examples
- Real API endpoints for live demos
- Template rendering for content pages
- Lifecycle hooks for initialization
- Middleware for security/logging

### Architecture

```
docs-site/
├── app.rb                    # Main FunApi application
├── Gemfile                   # Dependencies
├── templates/
│   ├── layouts/
│   │   └── docs.html.erb     # Main documentation layout
│   ├── pages/
│   │   ├── index.html.erb    # Landing page
│   │   ├── guide.html.erb    # Getting started guide
│   │   └── api.html.erb      # API reference
│   └── partials/
│       ├── _nav.html.erb     # Navigation
│       ├── _code.html.erb    # Code examples
│       └── _demo.html.erb    # Interactive demos
├── public/
│   ├── css/
│   └── js/
└── content/
    └── guides/               # Markdown content (optional)
```

### Key Features to Demonstrate

1. **Template Rendering**
   - Layout with consistent header/footer
   - Partials for reusable components
   - Dynamic content injection

2. **HTMX Integration**
   - Live code examples that execute
   - Interactive API explorer
   - Real-time search

3. **API Endpoints**
   - `/api/examples/:name` - Run example code
   - `/api/search` - Search documentation
   - `/docs/*` - Static documentation pages

4. **Lifecycle Hooks**
   - Load documentation content on startup
   - Warm template cache
   - Initialize search index

5. **Middleware**
   - Request logging
   - CORS for API endpoints
   - Caching headers for static content

### Sample Implementation

```ruby
# app.rb
require 'fun_api'
require 'fun_api/templates'
require 'fun_api/server/falcon'

templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/docs.html.erb'
)

DOCS_CONTENT = {}

app = FunApi::App.new(
  title: 'FunApi Documentation',
  version: '0.1.0'
) do |api|
  # Startup: Load documentation content
  api.on_startup do
    puts "Loading documentation..."
    Dir.glob('content/**/*.md').each do |file|
      key = File.basename(file, '.md')
      DOCS_CONTENT[key] = File.read(file)
    end
    puts "Loaded #{DOCS_CONTENT.size} documentation files"
  end

  # Middleware
  api.add_cors(allow_origins: ['*'])
  api.add_request_logger

  # Documentation pages
  api.get '/' do |_input, _req, _task|
    templates.response('pages/index.html.erb',
      title: 'FunApi - Async-first Ruby Web Framework')
  end

  api.get '/guide' do |_input, _req, _task|
    templates.response('pages/guide.html.erb',
      title: 'Getting Started',
      content: DOCS_CONTENT['getting-started'])
  end

  # Interactive examples API
  api.get '/api/examples/:name' do |input, _req, _task|
    name = input[:path]['name']
    example = load_example(name)
    
    if example
      [{code: example[:code], output: run_example(example)}, 200]
    else
      raise FunApi::HTTPException.new(status_code: 404, detail: "Example not found")
    end
  end

  # HTMX partial for code output
  api.post '/api/run' do |input, _req, _task|
    code = input[:body][:code]
    output = safe_eval(code)
    templates.response('partials/_output.html.erb', layout: false, output: output)
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

### Styling Approach
- Use Tailwind CSS or simple custom CSS
- Keep it minimal and fast
- Dark mode support
- Mobile responsive

### Content Structure

1. **Landing Page**
   - Hero with code example
   - Feature highlights
   - Quick start snippet

2. **Guide Section**
   - Installation
   - Hello World
   - Routes & Parameters
   - Validation
   - Middleware
   - Templates
   - Async Operations
   - Database Integration

3. **API Reference**
   - Auto-generated from code
   - Method signatures
   - Examples for each feature

4. **Examples**
   - Full working applications
   - HTMX integration
   - Database patterns

## Timeline

### Phase 1: Publishing Setup (1-2 hours)
- [ ] Create GitHub repository
- [ ] Update gemspec metadata
- [ ] Create v0.1.0 tag
- [ ] Publish to RubyGems (optional)

### Phase 2: Documentation Site MVP (4-6 hours)
- [ ] Create docs-site directory structure
- [ ] Implement basic layout and templates
- [ ] Add landing page with examples
- [ ] Add getting started guide
- [ ] Deploy to fly.io or similar

### Phase 3: Interactive Features (2-4 hours)
- [ ] Add HTMX-powered code examples
- [ ] Implement live API playground
- [ ] Add search functionality

### Phase 4: Polish (2-4 hours)
- [ ] Complete API documentation
- [ ] Add more examples
- [ ] Performance optimization
- [ ] SEO metadata

## Deployment Options

### fly.io (Recommended)
```toml
# fly.toml
app = "funapi-docs"
primary_region = "iad"

[build]
  builder = "heroku/buildpacks:22"

[http_service]
  internal_port = 3000
  force_https = true
```

### Docker
```dockerfile
FROM ruby:3.2-alpine
WORKDIR /app
COPY Gemfile* ./
RUN bundle install
COPY . .
EXPOSE 3000
CMD ["ruby", "app.rb"]
```

### Render.com
- Native Ruby support
- Easy from GitHub repo
- Free tier available

## Success Criteria

1. **Publishing**
   - [ ] Gem installable via `gem install fun_api` or git
   - [ ] Version tagged and documented

2. **Documentation Site**
   - [ ] All features documented with examples
   - [ ] Interactive code execution works
   - [ ] Responsive and accessible
   - [ ] < 1 second load time

3. **Dogfooding Validation**
   - [ ] No major issues discovered during development
   - [ ] Framework is pleasant to use
   - [ ] Any issues found are documented and fixed

## Notes

- Keep the docs site simple initially - complexity can come later
- Focus on getting the getting-started experience right
- Document any pain points discovered during dogfooding
- Consider adding a changelog page that pulls from CHANGELOG.md
