# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Response structured output modes" do
  let(:schema) do
    OpenRouter::Schema.define("test_user") do
      string :name, required: true
      integer :age, required: true
      string :email, format: "email"
    end
  end

  let(:response_format) do
    {
      type: "json_schema",
      json_schema: schema
    }
  end

  describe "#structured_output" do
    context "with valid JSON content" do
      let(:json_content) { '{"name": "John", "age": 30, "email": "john@example.com"}' }
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => json_content } }] }, response_format:) }

      context "with mode: :strict (default)" do
        it "parses and returns JSON object" do
          result = response.structured_output(mode: :strict)
          expect(result).to eq({ "name" => "John", "age" => 30, "email" => "john@example.com" })
        end

        it "validates against schema when available" do
          expect(schema).to receive(:validate).and_return(true)
          response.structured_output(mode: :strict, auto_heal: false)
        end

        it "uses strict mode by default" do
          result = response.structured_output
          expect(result).to eq({ "name" => "John", "age" => 30, "email" => "john@example.com" })
        end
      end

      context "with mode: :gentle" do
        it "parses and returns JSON object without validation" do
          result = response.structured_output(mode: :gentle)
          expect(result).to eq({ "name" => "John", "age" => 30, "email" => "john@example.com" })
        end

        it "does not validate against schema" do
          expect(schema).not_to receive(:validate)
          response.structured_output(mode: :gentle)
        end
      end
    end

    context "with invalid JSON content" do
      let(:invalid_json) { '{"name": "John", "age": thirty}' } # Invalid: age should be number
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => invalid_json } }] }, response_format:) }

      context "with mode: :strict" do
        it "raises StructuredOutputError on invalid JSON" do
          expect do
            response.structured_output(mode: :strict)
          end.to raise_error(OpenRouter::StructuredOutputError, /Failed to parse structured output/)
        end

        context "with auto_heal enabled" do
          let(:mock_client) do
            double("client",
                   configuration: double(auto_heal_responses: true, max_heal_attempts: 2,
                                         healer_model: "gpt-3.5-turbo"))
          end

          before do
            response.client = mock_client
          end

          it "attempts healing on parse failure" do
            expect(response).to receive(:heal_structured_response).and_return({ "name" => "John", "age" => 30 })
            result = response.structured_output(mode: :strict, auto_heal: true)
            expect(result).to eq({ "name" => "John", "age" => 30 })
          end
        end
      end

      context "with mode: :gentle" do
        it "returns nil on invalid JSON instead of raising" do
          result = response.structured_output(mode: :gentle)
          expect(result).to be_nil
        end

        it "does not attempt healing even if auto_heal is enabled" do
          expect(response).not_to receive(:heal_structured_response)
          response.structured_output(mode: :gentle)
        end
      end
    end

    context "with schema validation failures" do
      let(:invalid_data) { '{"name": "John", "age": "thirty", "email": "invalid-email"}' } # Wrong types
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => invalid_data } }] }, response_format:) }

      context "with mode: :strict" do
        it "raises StructuredOutputError on schema validation failure" do
          expect do
            response.structured_output(mode: :strict)
          end.to raise_error(OpenRouter::StructuredOutputError, /Schema validation failed/)
        end
      end

      context "with mode: :gentle" do
        it "returns parsed JSON even if schema validation would fail" do
          result = response.structured_output(mode: :gentle)
          expect(result).to eq({ "name" => "John", "age" => "thirty", "email" => "invalid-email" })
        end
      end
    end

    context "with no structured output content" do
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => "Just a regular text response" } }] }) }

      it "returns nil in both modes when no response_format is set" do
        expect(response.structured_output(mode: :strict)).to be_nil
        expect(response.structured_output(mode: :gentle)).to be_nil
      end
    end

    context "with invalid mode parameter" do
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => "{}" } }] }, response_format:) }

      it "raises ArgumentError for invalid mode" do
        expect do
          response.structured_output(mode: :invalid)
        end.to raise_error(ArgumentError, /Invalid mode: invalid. Must be :strict or :gentle/)
      end
    end

    context "auto_heal parameter behavior" do
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"broken": json}' } }] }, response_format:) }
      let(:mock_client) do
        double("client",
               configuration: double(auto_heal_responses: false, max_heal_attempts: 2, healer_model: "gpt-3.5-turbo"))
      end

      before do
        response.client = mock_client
      end

      it "respects explicit auto_heal: true override" do
        expect(response).to receive(:heal_structured_response).and_return({ "fixed" => "json" })
        result = response.structured_output(mode: :strict, auto_heal: true)
        expect(result).to eq({ "fixed" => "json" })
      end

      it "respects explicit auto_heal: false override" do
        expect(response).not_to receive(:heal_structured_response)
        expect do
          response.structured_output(mode: :strict, auto_heal: false)
        end.to raise_error(OpenRouter::StructuredOutputError)
      end

      it "ignores auto_heal in gentle mode" do
        expect(response).not_to receive(:heal_structured_response)
        result = response.structured_output(mode: :gentle, auto_heal: true)
        expect(result).to be_nil
      end
    end
  end
end
