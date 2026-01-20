# frozen_string_literal: true

require_relative 'test_helper'

class TestIntrospection < Minitest::Test
  def setup
    @user_schema = FunApi::Schema.define do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end

    @query_schema = FunApi::Schema.define do
      optional(:limit).filled(:integer)
    end

    @app = FunApi::App.new do |api|
      api.register(:db) { {} }
      api.register(:logger) { Logger.new($stdout) }
      api.register(:cache) { {} }

      api.add_cors
      api.add_request_logger

      api.get '/' do |_input, _req, _task|
        [{ message: 'home' }, 200]
      end

      api.get '/users', query: @query_schema, depends: [:db] do |_input, _req, _task, db:|
        [[], 200]
      end

      api.post '/users', body: @user_schema, depends: %i[db logger] do |input, _req, _task, db:, logger:|
        [input[:body], 201]
      end
    end
  end

  def test_introspect_returns_inspector
    assert_instance_of FunApi::Introspection::Inspector, @app.introspect
  end

  def test_introspect_routes_returns_collection
    assert_instance_of FunApi::Introspection::RouteCollection, @app.introspect.routes
  end

  def test_introspect_routes_count
    assert_equal 3, @app.introspect.routes.count
  end

  def test_introspect_routes_excludes_internal
    assert_equal 3, @app.introspect.routes.count
    internal_routes = @app.introspect.all_routes.count - @app.introspect.routes.count
    assert internal_routes >= 2, 'Should have at least openapi internal routes'
  end

  def test_route_info_basic_properties
    route = @app.introspect.routes.find_by(verb: 'GET', path: '/users')

    assert_equal 'GET', route.verb
    assert_equal '/users', route.path
    assert_equal [], route.path_params
    assert_equal [:db], route.dependencies
    refute route.has_body_schema?
    assert route.has_query_schema?
    refute route.internal?
  end

  def test_route_info_path_params
    route = @app.introspect.route('GET', '/')

    assert_equal [], route.path_params
  end

  def test_route_info_dependencies
    route = @app.introspect.routes.find_by(verb: 'POST', path: '/users')

    assert_equal %i[db logger], route.dependencies
    assert route.uses_dependency?(:db)
    assert route.uses_dependency?(:logger)
    refute route.uses_dependency?(:cache)
  end

  def test_route_info_schemas
    route = @app.introspect.routes.find_by(verb: 'POST', path: '/users')

    assert route.has_body_schema?
    refute route.has_query_schema?
    refute route.has_response_schema?
  end

  def test_route_collection_where_verb
    get_routes = @app.introspect.routes.where_verb('GET')

    assert_equal 2, get_routes.count
    assert(get_routes.all? { |r| r.verb == 'GET' })
  end

  def test_route_collection_where_uses_dependency
    db_routes = @app.introspect.routes.where_uses_dependency(:db)

    assert_equal 2, db_routes.count
    assert(db_routes.all? { |r| r.uses_dependency?(:db) })
  end

  def test_route_collection_where_has_body_schema
    routes_with_body = @app.introspect.routes.where_has_body_schema

    assert_equal 1, routes_with_body.count
    assert_equal 'POST', routes_with_body.first.verb
  end

  def test_route_collection_search
    user_routes = @app.introspect.routes.search('user')

    assert_equal 2, user_routes.count
    assert(user_routes.all? { |r| r.path.include?('user') })
  end

  def test_dependencies_collection
    deps = @app.introspect.dependencies

    assert_equal 3, deps.count
    assert_equal %i[db logger cache].sort, deps.names.sort
  end

  def test_dependency_info_basic
    dep = @app.introspect.dependency(:db)

    assert_equal :db, dep.name
    assert_equal :simple, dep.type
    assert dep.callable?
  end

  def test_dependency_info_usage
    dep = @app.introspect.dependency(:db)

    assert_equal 2, dep.used_by_count
    assert_equal 2, dep.used_by.length
  end

  def test_dependency_collection_unused
    unused = @app.introspect.dependencies.unused

    assert_equal 1, unused.count
    assert_equal :cache, unused.first.name
  end

  def test_dependency_collection_most_used
    most_used = @app.introspect.dependencies.most_used(2)

    assert_equal 2, most_used.count
    assert_equal :db, most_used.first.name
  end

  def test_schemas_collection
    schemas = @app.introspect.schemas

    assert_equal 2, schemas.count
  end

  def test_schema_info_fields
    schema = @app.introspect.schemas.where_has_field(:name).first

    assert_includes schema.fields, :name
    assert_includes schema.fields, :email
  end

  def test_schema_info_required_optional
    user_schema_info = @app.introspect.schemas.where_has_field(:name).first

    assert_equal %i[name email].sort, user_schema_info.required_fields.sort
    assert_equal [], user_schema_info.optional_fields
  end

  def test_schema_collection_where_has_field
    email_schemas = @app.introspect.schemas.where_has_field(:email)

    assert_equal 1, email_schemas.count
  end

  def test_middleware_collection
    middleware = @app.introspect.middleware

    assert_equal 2, middleware.count
  end

  def test_middleware_info_basic
    mw = @app.introspect.middleware.first

    assert_equal 'FunApi::Middleware::Cors', mw.class_name
    assert_equal 0, mw.position
    assert mw.builtin?
  end

  def test_middleware_collection_builtin
    builtin_mw = @app.introspect.middleware.builtin

    assert_equal 2, builtin_mw.count
  end

  def test_stats
    stats = @app.introspect.stats

    assert_equal 3, stats[:routes]
    assert_equal 3, stats[:dependencies]
    assert_equal 2, stats[:schemas]
    assert_equal 2, stats[:middleware]
    assert_equal :db, stats[:most_common_dependency]
  end

  def test_validate
    health = @app.introspect.validate

    assert health[:issues].any?
    assert_equal 1, health[:issues].count
    assert_equal :unused_dependency, health[:issues].first[:type]
    assert health[:score] > 0
  end

  def test_relationships
    rels = @app.introspect.relationships

    assert rels.key?(:db)
    assert_equal 2, rels[:db][:routes]
  end

  def test_fingerprint
    fingerprint = @app.introspect.fingerprint

    assert_instance_of String, fingerprint
    assert_equal 64, fingerprint.length
  end

  def test_changed_since
    fp1 = @app.introspect.fingerprint

    refute @app.introspect.changed_since?(fp1)

    @app.get '/new' do |_input, _req, _task|
      [{}, 200]
    end

    @app.introspect.clear_cache

    assert @app.introspect.changed_since?(fp1)
  end

  def test_to_json
    json = @app.introspect.to_json

    assert_instance_of String, json
    assert JSON.parse(json)
  end

  def test_route_to_h
    route = @app.introspect.routes.first
    hash = route.to_h

    assert hash.key?(:verb)
    assert hash.key?(:path)
    assert hash.key?(:dependencies)
  end

  def test_collection_enumerable
    routes = @app.introspect.routes

    assert_respond_to routes, :each
    assert_respond_to routes, :map
    assert_respond_to routes, :select
  end

  def test_collection_where_with_block
    routes = @app.introspect.routes.where { |r| r.verb == 'POST' }

    assert_equal 1, routes.count
    assert_equal 'POST', routes.first.verb
  end

  def test_collection_group_by
    grouped = @app.introspect.routes.group_by(&:verb)

    assert grouped.key?('GET')
    assert grouped.key?('POST')
    assert_equal 2, grouped['GET'].length
  end
end
