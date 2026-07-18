# frozen_string_literal: true

module FunApi
  class Router
    RouteDefinition = Struct.new(
      :verb, :path, :path_schema, :body_schema, :query_schema,
      :response_schema, :depends, :tags, :block,
      keyword_init: true
    )

    Inclusion = Struct.new(:router, :prefix, :depends, :tags, keyword_init: true)

    def initialize(prefix: "", tags: [], depends: {})
      @prefix = normalize_prefix(prefix)
      @tags = Array(tags)
      @depends = self.class.coerce_depends(depends)
      @routes = []
      @inclusions = []

      yield self if block_given?
    end

    def get(route_path, path: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &block)
      add(:get, route_path, path_schema: path, query_schema: query, response_schema: response_schema, depends: depends, tags: tags, &block)
    end

    def post(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &block)
      add(:post, route_path, path_schema: path, body_schema: body, query_schema: query, response_schema: response_schema, depends: depends, tags: tags, &block)
    end

    def put(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &block)
      add(:put, route_path, path_schema: path, body_schema: body, query_schema: query, response_schema: response_schema, depends: depends, tags: tags, &block)
    end

    def patch(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &block)
      add(:patch, route_path, path_schema: path, body_schema: body, query_schema: query, response_schema: response_schema, depends: depends, tags: tags, &block)
    end

    def delete(route_path, path: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &block)
      add(:delete, route_path, path_schema: path, query_schema: query, response_schema: response_schema, depends: depends, tags: tags, &block)
    end

    def include_router(router, prefix: "", depends: {}, tags: [])
      @inclusions << Inclusion.new(
        router: router,
        prefix: normalize_prefix(prefix),
        depends: self.class.coerce_depends(depends),
        tags: Array(tags)
      )
      self
    end

    def each_route(inherited_prefix: "", inherited_depends: {}, inherited_tags: [], &block)
      prefix = join_paths(inherited_prefix, @prefix)
      depends = inherited_depends.merge(@depends)
      tags = inherited_tags | @tags

      @routes.each do |route|
        block.call(
          verb: route.verb,
          path: join_paths(prefix, route.path),
          path_schema: route.path_schema,
          body_schema: route.body_schema,
          query_schema: route.query_schema,
          response_schema: route.response_schema,
          depends: depends.merge(route.depends),
          tags: tags | route.tags,
          block: route.block
        )
      end

      @inclusions.each do |inclusion|
        inclusion.router.each_route(
          inherited_prefix: join_paths(prefix, inclusion.prefix),
          inherited_depends: depends.merge(inclusion.depends),
          inherited_tags: tags | inclusion.tags,
          &block
        )
      end
    end

    def self.coerce_depends(depends)
      case depends
      when nil
        {}
      when Array
        depends.each_with_object({}) { |name, acc| acc[name.to_sym] = name.to_sym }
      when Hash
        depends.transform_keys(&:to_sym)
      else
        raise ArgumentError, "depends must be an Array or Hash"
      end
    end

    private

    def add(verb, path, path_schema: nil, body_schema: nil, query_schema: nil, response_schema: nil, depends: nil, tags: nil, &block)
      raise ArgumentError, "#{verb} requires a block" unless block

      @routes << RouteDefinition.new(
        verb: verb.to_s.upcase,
        path: normalize_prefix(path),
        path_schema: path_schema,
        body_schema: body_schema,
        query_schema: query_schema,
        response_schema: response_schema,
        depends: self.class.coerce_depends(depends),
        tags: Array(tags),
        block: block
      )
      self
    end

    def normalize_prefix(prefix)
      value = prefix.to_s
      return "" if value.empty? || value == "/"

      value = "/#{value}" unless value.start_with?("/")
      value.chomp("/")
    end

    def join_paths(base, segment)
      joined = "#{base}#{segment}"
      joined.empty? ? "/" : joined
    end
  end
end
