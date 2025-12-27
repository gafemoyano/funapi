# frozen_string_literal: true

require_relative "../models/tag"

module Routes
  module Tags
    def self.register(api)
      # Get all tags
      api.get "/api/tags" do |_input, _req, _task|
        tags = Tag.all.map(&:name)
        [{ tags: tags }, 200]
      end
    end
  end
end
