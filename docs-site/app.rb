# frozen_string_literal: true

require 'funapi'
require 'funapi/templates'
require 'funapi/server/falcon'
require 'kramdown'
require 'kramdown-parser-gfm'
require 'rouge'

class DocsRenderer
  def initialize(content_dir:)
    @content_dir = Pathname.new(content_dir)
    @cache = {}
  end

  def render(path)
    file_path = @content_dir.join("#{path}.md")
    raise FunApi::HTTPException.new(status_code: 404, detail: 'Page not found') unless file_path.exist?

    @cache[path] ||= begin
      content = file_path.read
      frontmatter, body = parse_frontmatter(content)
      html = Kramdown::Document.new(
        body,
        input: 'GFM',
        syntax_highlighter: 'rouge',
        syntax_highlighter_opts: { default_lang: 'ruby' }
      ).to_html

      { frontmatter: frontmatter, html: html }
    end
  end

  def navigation
    @navigation ||= build_navigation
  end

  private

  def parse_frontmatter(content)
    if content.start_with?('---')
      parts = content.split('---', 3)
      frontmatter = parse_yaml(parts[1])
      body = parts[2]
      [frontmatter, body]
    else
      [{}, content]
    end
  end

  def parse_yaml(yaml_str)
    result = {}
    yaml_str.each_line do |line|
      result[::Regexp.last_match(1).to_sym] = ::Regexp.last_match(2).strip if line =~ /^(\w+):\s*(.+)$/
    end
    result
  end

  def build_navigation
    [
      {
        title: 'Getting Started',
        items: [
          { path: 'getting-started/at-glance', title: 'At Glance' },
          { path: 'getting-started/quick-start', title: 'Quick Start' },
          { path: 'getting-started/key-concepts', title: 'Key Concepts' }
        ]
      },
      {
        title: 'Essential',
        items: [
          { path: 'essential/routing', title: 'Routing' },
          { path: 'essential/handler', title: 'Handler' },
          { path: 'essential/validation', title: 'Validation' },
          { path: 'essential/openapi', title: 'OpenAPI' },
          { path: 'essential/lifecycle', title: 'Lifecycle' },
          { path: 'essential/middleware', title: 'Middleware' }
        ]
      },
      {
        title: 'Patterns',
        items: [
          { path: 'patterns/async-operations', title: 'Async Operations' },
          { path: 'patterns/best-practices', title: 'Best Practices' },
          { path: 'patterns/dependencies', title: 'Dependencies' },
          { path: 'patterns/background-tasks', title: 'Background Tasks' },
          { path: 'patterns/templates', title: 'Templates' },
          { path: 'patterns/error-handling', title: 'Error Handling' },
          { path: 'patterns/response-schema', title: 'Response Schema' },
          { path: 'patterns/database', title: 'Database' },
          { path: 'patterns/testing', title: 'Testing' },
          { path: 'patterns/deployment', title: 'Deployment' }
        ]
      }
    ]
  end
end

# Get the docs-site directory path relative to this script
docs_site_dir = __dir__
docs = DocsRenderer.new(content_dir: File.join(docs_site_dir, 'content'))
templates = FunApi::Templates.new(
  directory: File.join(docs_site_dir, 'templates'),
  layout: 'layouts/docs.html.erb'
)

app = FunApi::App.new(
  title: 'FunApi Documentation',
  version: '0.1.0',
  description: 'Documentation for the FunApi framework'
) do |api|
  api.use Rack::Static, urls: ['/css'], root: File.join(docs_site_dir, 'public')
  api.add_request_logger

  api.get '/' do |_input, _req, _task|
    page = docs.render('index')
    templates.response(
      'page.html.erb',
      title: page[:frontmatter][:title] || 'FunApi',
      content: page[:html],
      nav: docs.navigation,
      current_path: 'index'
    )
  end

  api.get '/docs/:section/:page' do |input, _req, _task|
    path = "#{input[:path]['section']}/#{input[:path]['page']}"
    page = docs.render(path)
    templates.response(
      'page.html.erb',
      title: page[:frontmatter][:title] || 'FunApi',
      content: page[:html],
      nav: docs.navigation,
      current_path: path
    )
  end
end

FunApi::Server::Falcon.start(app, port: 3000) if __FILE__ == $0
