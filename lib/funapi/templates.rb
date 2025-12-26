# frozen_string_literal: true

require "erb"
require "pathname"
require_relative "template_response"
require_relative "exceptions"

module FunApi
  class Templates
    def initialize(directory:, layout: nil)
      @directory = Pathname.new(directory)
      @layout = layout
      @cache = {}
    end

    def with_layout(layout)
      ScopedTemplates.new(self, layout)
    end

    def render(name, layout: nil, **context)
      content = render_template(name, **context)

      layout_to_use = determine_layout(layout)
      if layout_to_use
        render_with_layout(layout_to_use, content, **context)
      else
        content
      end
    end

    def response(name, status: 200, headers: {}, layout: nil, **context)
      html = render(name, layout: layout, **context)
      TemplateResponse.new(html, status: status, headers: headers)
    end

    def render_partial(name, **context)
      render_template(name, **context)
    end

    private

    def determine_layout(layout_override)
      return nil if layout_override == false
      return layout_override if layout_override

      @layout
    end

    def render_with_layout(layout_name, content, **context)
      template = load_template(layout_name)
      template_context = TemplateContext.new(self, context, content: content)
      template.result(template_context.get_binding)
    end

    def render_template(name, **context)
      template = load_template(name)
      template_context = TemplateContext.new(self, context)
      template.result(template_context.get_binding)
    end

    def load_template(name)
      path = @directory.join(name)
      raise TemplateNotFoundError.new(name) unless path.exist?

      @cache[name] ||= ERB.new(path.read, trim_mode: "-")
    end
  end

  class TemplateContext
    def initialize(templates, context, content: nil)
      @templates = templates
      @content = content
      context.each do |key, value|
        define_singleton_method(key) { value }
      end
    end

    def render_partial(name, **context)
      @templates.render_partial(name, **context)
    end

    def yield_content
      @content
    end

    def get_binding
      binding
    end
  end

  class ScopedTemplates
    def initialize(templates, layout)
      @templates = templates
      @layout = layout
    end

    def render(name, layout: nil, **context)
      effective_layout = layout.nil? ? @layout : layout
      @templates.render(name, layout: effective_layout, **context)
    end

    def response(name, status: 200, headers: {}, layout: nil, **context)
      effective_layout = layout.nil? ? @layout : layout
      @templates.response(name, status: status, headers: headers, layout: effective_layout, **context)
    end

    def render_partial(name, **context)
      @templates.render_partial(name, **context)
    end
  end
end
