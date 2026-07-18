# frozen_string_literal: true

require "test_helper"
require "funapi/test_client"

class TestDependencyOverrides < Minitest::Test
  class RealDb
    def users
      [{id: 1, name: "real"}]
    end
  end

  class FakeDb
    def users
      [{id: 99, name: "fake"}]
    end
  end

  def build_app
    FunApi::App.new do |api|
      api.register(:db) { RealDb.new }

      api.get "/users", depends: [:db] do |_input, _req, db:|
        [{users: db.users}, 200]
      end

      current_user = FunApi.Depends(-> { {id: 1, name: "real-user"} })
      api.get "/me", depends: {user: current_user} do |_input, _req, user:|
        [user, 200]
      end
    end
  end

  def test_override_container_dependency_with_object
    app = build_app
    app.override_dependency(:db, FakeDb.new)
    client = FunApi::TestClient.new(app)

    res = client.get("/users")
    assert_equal "fake", res.json[:users].first[:name]
  end

  def test_override_with_callable
    app = build_app
    app.override_dependency(:db, -> { FakeDb.new })
    client = FunApi::TestClient.new(app)

    assert_equal "fake", client.get("/users").json[:users].first[:name]
  end

  def test_override_depends_by_param_name
    app = build_app
    app.override_dependency(:user, {id: 2, name: "override-user"})
    client = FunApi::TestClient.new(app)

    assert_equal "override-user", client.get("/me").json[:name]
  end

  def test_reset_overrides_restores_real_dependency
    app = build_app
    app.override_dependency(:db, FakeDb.new)
    app.reset_overrides!
    client = FunApi::TestClient.new(app)

    assert_equal "real", client.get("/users").json[:users].first[:name]
  end
end
