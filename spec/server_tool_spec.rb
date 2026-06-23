# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::ServerTool do
  describe "building server tool definitions" do
    it "builds an openrouter:web_search tool with nested parameters" do
      tool = described_class.web_search(engine: "exa", max_results: 5)

      expect(tool.to_h).to eq(
        type: "openrouter:web_search",
        parameters: { engine: "exa", max_results: 5 }
      )
    end

    it "omits the parameters key when no parameters are given" do
      expect(described_class.web_search.to_h).to eq(type: "openrouter:web_search")
    end

    it "builds an openrouter:web_fetch tool" do
      expect(described_class.web_fetch.to_h).to eq(type: "openrouter:web_fetch")
    end

    it "builds a generic server tool by short name" do
      expect(described_class.new("datetime").to_h).to eq(type: "openrouter:datetime")
    end

    it "does not double-prefix a name that already includes the openrouter: namespace" do
      expect(described_class.new("openrouter:web_search").to_h).to eq(type: "openrouter:web_search")
    end

    it "reports its type" do
      expect(described_class.web_search.type).to eq("openrouter:web_search")
    end
  end
end

RSpec.describe "OpenRouter server tools in requests" do
  let(:client) { OpenRouter::Client.new(access_token: "test") }
  let(:messages) { [{ role: "user", content: "What's the latest news?" }] }
  let(:mock_response) do
    { "id" => "c1", "model" => "openai/gpt-4o-mini",
      "choices" => [{ "index" => 0, "message" => { "role" => "assistant", "content" => "ok" }, "finish_reason" => "stop" }] }
  end

  it "serializes a ServerTool into the request tools array" do
    captured = nil
    allow(client).to receive(:post) do |parameters:, **|
      captured = parameters
      mock_response
    end

    client.complete(messages, model: "openai/gpt-4o-mini",
                              tools: [OpenRouter::ServerTool.web_search(max_results: 3)])

    expect(captured[:tools]).to eq([{ type: "openrouter:web_search", parameters: { max_results: 3 } }])
  end

  it "serializes function tools and server tools together" do
    function_tool = OpenRouter::Tool.define do
      name "get_time"
      description "Get the current time"
    end
    captured = nil
    allow(client).to receive(:post) do |parameters:, **|
      captured = parameters
      mock_response
    end

    client.complete(messages, model: "openai/gpt-4o-mini",
                              tools: [function_tool, OpenRouter::ServerTool.web_fetch])

    types = captured[:tools].map { |t| t[:type] }
    expect(types).to eq(%w[function openrouter:web_fetch])
  end

  it "does not raise a function_calling capability error for server-tools-only requests in strict mode" do
    client.configuration.strict_mode = true
    allow(OpenRouter::ModelRegistry).to receive(:has_capability?).and_return(false)
    allow(client).to receive(:post).and_return(mock_response)

    expect do
      client.complete(messages, model: "some/model", tools: [OpenRouter::ServerTool.web_search])
    end.not_to raise_error
  end
end
