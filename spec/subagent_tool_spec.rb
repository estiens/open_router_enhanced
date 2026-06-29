# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::SubagentTool do
  describe "#to_h" do
    it "emits the openrouter:subagent server-tool shape with all fields" do
      tool = described_class.new(
        model: "z-ai/glm-5.2",
        instructions: "Be concise.",
        max_completion_tokens: 1024,
        temperature: 0.2,
        reasoning: { effort: "low" }
      )

      expect(tool.to_h).to eq(
        type: "openrouter:subagent",
        parameters: {
          model: "z-ai/glm-5.2",
          instructions: "Be concise.",
          max_completion_tokens: 1024,
          temperature: 0.2,
          reasoning: { effort: "low" }
        }
      )
    end

    it "omits nil optional fields (compacted)" do
      tool = described_class.new(model: "z-ai/glm-5.2")

      expect(tool.to_h).to eq(
        type: "openrouter:subagent",
        parameters: { model: "z-ai/glm-5.2" }
      )
    end
  end

  describe "validation" do
    it "raises when model keyword is missing" do
      expect { described_class.new(instructions: "hi") }
        .to raise_error(ArgumentError, /missing keyword/)
    end

    it "raises ArgumentError when model is blank" do
      expect { described_class.new(model: "  ") }
        .to raise_error(ArgumentError, /model is required/)
    end
  end

  it "is a Tool so it serializes through the tools array" do
    tool = described_class.new(model: "z-ai/glm-5.2")
    expect(tool).to be_a(OpenRouter::Tool)
  end

  it "returns nil for parameters (server tool has no function parameters)" do
    tool = described_class.new(model: "z-ai/glm-5.2")
    expect(tool.parameters).to be_nil
  end

  describe "serialization through Client#complete" do
    let(:client) { OpenRouter::Client.new(access_token: "test-token") }
    let(:mock_response) do
      {
        "id" => "chatcmpl-1",
        "model" => "anthropic/claude-3.5-sonnet",
        "choices" => [{ "message" => { "role" => "assistant", "content" => "done" }, "finish_reason" => "stop" }],
        "usage" => { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 }
      }
    end

    before do
      # Keep the unit test hermetic: complete() calls warn_if_unsupported -> ModelRegistry.
      allow(OpenRouter::ModelRegistry).to receive(:has_capability?).and_return(true)
    end

    it "passes the subagent tool through the tools array" do
      sub = described_class.new(model: "z-ai/glm-5.2", instructions: "Be concise.")

      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          tools: [{ type: "openrouter:subagent",
                    parameters: { model: "z-ai/glm-5.2", instructions: "Be concise." } }]
        )
      ).and_return(mock_response)

      client.complete([{ role: "user", content: "hi" }],
                      model: "anthropic/claude-3.5-sonnet", tools: [sub])
    end
  end
end
