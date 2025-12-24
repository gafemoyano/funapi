module FunApi
  class HTTPException < StandardError
    attr_reader :status_code, :detail, :headers

    def initialize(status_code:, detail: nil, headers: nil)
      @status_code = status_code
      @detail = detail || default_detail
      @headers = headers || {}
      super(@detail.to_s)
    end

    def to_response
      [
        status_code,
        {"content-type" => "application/json"}.merge(headers),
        [JSON.dump(detail: detail)]
      ]
    end

    private

    def default_detail
      case status_code
      when 400 then "Bad Request"
      when 401 then "Unauthorized"
      when 403 then "Forbidden"
      when 404 then "Not Found"
      when 422 then "Unprocessable Entity"
      when 500 then "Internal Server Error"
      else "Error"
      end
    end
  end

  class ValidationError < HTTPException
    attr_reader :errors

    def initialize(errors:, headers: nil)
      @errors = errors
      super(status_code: 422, detail: format_errors(errors), headers: headers)
    end

    def to_response
      [
        status_code,
        {"content-type" => "application/json"}.merge(headers),
        [JSON.dump(detail: detail)]
      ]
    end

    private

    def format_errors(errors)
      errors.messages.map do |error|
        {
          loc: error.path.map(&:to_s),
          msg: error.text,
          type: "value_error"
        }
      end
    end
  end

  class TemplateNotFoundError < StandardError
    attr_reader :template_name

    def initialize(template_name)
      @template_name = template_name
      super("Template not found: #{template_name}")
    end
  end
end
