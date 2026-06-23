# frozen_string_literal: true

require "json"

module OpenRouter
  module HTTP
    def get(path:)
      response = conn.get(uri(path:)) do |req|
        req.headers = headers
      end
      normalize_body(response&.body)
    end

    def post(path:, parameters:)
      response = conn.post(uri(path:)) do |req|
        if parameters[:stream].respond_to?(:call)
          req.options.on_data = to_json_stream(user_proc: parameters[:stream])
          parameters[:stream] = true # Necessary to tell OpenRouter to stream.
        end

        req.headers = headers
        req.body = parameters.to_json
      end
      normalize_body(response&.body)
    end

    def multipart_post(path:, parameters: nil)
      response = conn(multipart: true).post(uri(path:)) do |req|
        req.headers = headers.merge({ "Content-Type" => "multipart/form-data" })
        req.body = multipart_parameters(parameters)
      end
      normalize_body(response&.body)
    end

    def delete(path:)
      response = conn.delete(uri(path:)) do |req|
        req.headers = headers
      end
      normalize_body(response&.body)
    end

    private

    # Normalize response body - parse JSON when middleware is not available
    def normalize_body(body)
      return body if OpenRouter::HAS_JSON_MW # Let middleware handle it
      return body unless body.is_a?(String)

      begin
        JSON.parse(body)
      rescue JSON::ParserError
        body # Return original if not valid JSON
      end
    end

    # Given a proc, returns an outer proc that can be used to iterate over a JSON stream of chunks.
    # For each chunk, the inner user_proc is called giving it the JSON object. The JSON object could
    # be a data object or an error object as described in the OpenRouter API documentation.
    #
    # If the JSON object for a given data or error message is invalid, it is ignored.
    #
    # @param user_proc [Proc] The inner proc to call for each JSON object in the chunk.
    # @return [Proc] An outer proc that iterates over a raw stream, converting it to JSON.
    def to_json_stream(user_proc:)
      buffer = +""

      proc do |chunk, _|
        buffer << chunk

        # SSE messages are newline-delimited. A single network chunk may contain
        # several complete lines and/or end mid-line, so we only process whole
        # lines and keep any trailing partial line buffered for the next chunk.
        while (newline_index = buffer.index("\n"))
          line = buffer.slice!(0..newline_index)
          process_stream_line(line.chomp, user_proc)
        end

        # A complete, well-formed data line may arrive without a trailing newline
        # (e.g. the final event). Emit it eagerly once it fully parses; a partial
        # line won't parse, so it stays buffered for the next chunk.
        buffer.clear if process_stream_line(buffer, user_proc)
      end
    end

    # Returns true when a valid data/error line was parsed and dispatched.
    def process_stream_line(line, user_proc)
      match = line.match(/\A(?:data|error):\s*(\{.*\})\s*\z/i)
      return false unless match

      parsed_chunk = JSON.parse(match[1])

      # Trigger on_stream_chunk callback if available
      trigger_callbacks(:on_stream_chunk, parsed_chunk) if respond_to?(:trigger_callbacks)

      user_proc.call(parsed_chunk)
      true
    rescue JSON::ParserError
      # Ignore invalid JSON.
      false
    end

    def conn(multipart: false)
      Faraday.new do |f|
        f.options[:timeout] = configuration.request_timeout
        f.request(:multipart) if multipart
        # NOTE: Removed MiddlewareErrors reference - was undefined and @log_errors was never set
        f.response :raise_error
        f.response :json if OpenRouter::HAS_JSON_MW

        configuration.faraday_config&.call(f)
      end
    end

    def uri(path:)
      base = configuration.uri_base.sub(%r{/\z}, "")
      ver = configuration.api_version.to_s.sub(%r{^/}, "").sub(%r{/\z}, "")
      p = path.to_s.sub(%r{^/}, "")
      [base, ver, p].reject(&:empty?).join("/")
    end

    def headers
      {
        "Authorization" => "Bearer #{configuration.access_token}",
        "Content-Type" => "application/json",
        "X-Title" => "OpenRouter Ruby Client",
        "HTTP-Referer" => "https://github.com/OlympiaAI/open_router"
      }.merge(configuration.extra_headers)
    end

    def multipart_parameters(parameters)
      parameters&.transform_values do |value|
        next value unless value.is_a?(File)

        # Doesn't seem like OpenRouter needs mime_type yet, so not worth
        # the library to figure this out. Hence the empty string
        # as the second argument.
        Faraday::UploadIO.new(value, "", value.path)
      end
    end
  end
end
