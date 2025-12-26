# frozen_string_literal: true

module FunApi
  class TemplateResponse
    attr_reader :body, :status, :headers

    def initialize(body, status: 200, headers: {})
      @body = body
      @status = status
      @headers = {"content-type" => "text/html; charset=utf-8"}.merge(headers)
    end

    def to_response
      [status, headers, [body]]
    end
  end
end
