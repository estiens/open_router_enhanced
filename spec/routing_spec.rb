# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::Routing do
  let(:client) { OpenRouter::Client.new(access_token: "test-token") }
  let(:messages) { [{ role: "user", content: "Write a merge function." }] }
  let(:mock_response) do
    {
      "id" => "chatcmpl-1",
      "model" => "anthropic/claude-3.5-sonnet",
      "choices" => [{ "message" => { "role" => "assistant", "content" => "ok" }, "finish_reason" => "stop" }],
      "usage" => { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 }
    }
  end

  describe "#pareto_complete" do
    it "routes to openrouter/pareto-code with a pareto-router plugin" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          model: "openrouter/pareto-code",
          plugins: [{ id: "pareto-router", min_coding_score: 0.8 }]
        )
      ).and_return(mock_response)

      client.pareto_complete(messages, min_coding_score: 0.8)
    end

    it "omits min_coding_score when not given (server defaults apply)" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          model: "openrouter/pareto-code",
          plugins: [{ id: "pareto-router" }]
        )
      ).and_return(mock_response)

      client.pareto_complete(messages)
    end

    it "forwards extra options like temperature" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(model: "openrouter/pareto-code", temperature: 0.3)
      ).and_return(mock_response)

      client.pareto_complete(messages, min_coding_score: 0.5, temperature: 0.3)
    end

    it "merges into a caller-supplied plugins array without clobbering" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          plugins: [{ id: "web" }, { id: "pareto-router", min_coding_score: 0.7 }]
        )
      ).and_return(mock_response)

      client.pareto_complete(messages, min_coding_score: 0.7, plugins: [{ id: "web" }])
    end

    it "raises ArgumentError when min_coding_score is out of range" do
      expect { client.pareto_complete(messages, min_coding_score: 1.5) }
        .to raise_error(ArgumentError, /min_coding_score/)
      expect { client.pareto_complete(messages, min_coding_score: -0.1) }
        .to raise_error(ArgumentError, /min_coding_score/)
    end

    it "raises ArgumentError when min_coding_score is not numeric" do
      expect { client.pareto_complete(messages, min_coding_score: "high") }
        .to raise_error(ArgumentError, /min_coding_score/)
    end
  end

  describe "#fuse" do
    it "routes to openrouter/fusion with a fusion plugin (panel + judge)" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          model: "openrouter/fusion",
          plugins: [{ id: "fusion",
                      analysis_models: ["deepseek/deepseek-chat", "google/gemini-flash-1.5"],
                      model: "deepseek/deepseek-chat" }]
        )
      ).and_return(mock_response)

      client.fuse(messages,
                  analysis_models: ["deepseek/deepseek-chat", "google/gemini-flash-1.5"],
                  judge: "deepseek/deepseek-chat")
    end

    it "supports preset and max_tool_calls and omits nil fields" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          model: "openrouter/fusion",
          plugins: [{ id: "fusion", preset: "general-budget", max_tool_calls: 4 }]
        )
      ).and_return(mock_response)

      client.fuse(messages, preset: "general-budget", max_tool_calls: 4)
    end

    it "raises ArgumentError when analysis_models is empty" do
      expect { client.fuse(messages, analysis_models: []) }
        .to raise_error(ArgumentError, /analysis_models/)
    end

    it "raises ArgumentError when analysis_models has more than 8 entries" do
      expect { client.fuse(messages, analysis_models: Array.new(9, "a/b")) }
        .to raise_error(ArgumentError, /analysis_models/)
    end

    it "raises ArgumentError when max_tool_calls is out of range" do
      expect { client.fuse(messages, max_tool_calls: 0) }
        .to raise_error(ArgumentError, /max_tool_calls/)
      expect { client.fuse(messages, max_tool_calls: 17) }
        .to raise_error(ArgumentError, /max_tool_calls/)
    end
  end
end
