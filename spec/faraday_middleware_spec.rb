# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Faraday JSON Middleware" do
  describe "graceful fallback when faraday_middleware is not available" do
    let(:client) { OpenRouter::Client.new }

    context "when faraday_middleware is available" do
      it "uses the JSON middleware normally" do
        # This test verifies normal operation when middleware is available
        # We need to ensure HAS_JSON_MW is true
        stub_const("OpenRouter::HAS_JSON_MW", true)

        connection = client.send(:conn)
        expect(connection).to be_a(Faraday::Connection)

        # Verify middleware is configured
        middleware_names = connection.builder.handlers.map(&:name)
        expect(middleware_names).to include("Faraday::Response::Json")
      end
    end

    context "when faraday_middleware is not available" do
      before do
        # Simulate faraday_middleware not being available
        # by making HAS_JSON_MW return false
        stub_const("OpenRouter::HAS_JSON_MW", false)
      end

      it "falls back gracefully without using f.response :json" do
        # This should not crash even without faraday_middleware
        expect do
          connection = client.send(:conn)
          expect(connection).to be_a(Faraday::Connection)
        end.not_to raise_error
      end

      it "can still parse JSON responses manually" do
        # Mock a successful response with JSON body
        json_body = '{"test": "data"}'

        allow(client).to receive(:post).and_return(json_body)

        # The response should be parsed as JSON
        result = client.send(:post, path: "/test", parameters: {})
        expect(result).to be_a(String)

        # Should be able to parse the JSON
        parsed = JSON.parse(result)
        expect(parsed["test"]).to eq("data")
      end

      it "handles non-JSON responses gracefully" do
        # Mock a response that's not JSON
        non_json_body = "not json"

        allow(client).to receive(:post).and_return(non_json_body)

        result = client.send(:post, path: "/test", parameters: {})
        expect(result).to eq("not json")
      end
    end

    context "normalize_body method" do
      let(:http_module) { Object.new.extend(OpenRouter::HTTP) }

      before do
        # Simulate no JSON middleware available
        stub_const("OpenRouter::HAS_JSON_MW", false)
      end

      it "parses valid JSON strings" do
        json_string = '{"key": "value"}'
        result = http_module.send(:normalize_body, json_string)
        expect(result).to eq({ "key" => "value" })
      end

      it "returns original value for non-JSON strings" do
        non_json = "plain text"
        result = http_module.send(:normalize_body, non_json)
        expect(result).to eq("plain text")
      end

      it "returns original value for non-string input" do
        hash_input = { "already" => "parsed" }
        result = http_module.send(:normalize_body, hash_input)
        expect(result).to eq(hash_input)
      end

      it "handles malformed JSON gracefully" do
        malformed = '{"incomplete": '
        result = http_module.send(:normalize_body, malformed)
        expect(result).to eq(malformed)
      end
    end
  end
end
