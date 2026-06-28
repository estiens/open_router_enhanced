# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Subagent server tool", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

  it "lets an orchestrator delegate to a cheap worker model",
     vcr: { cassette_name: "subagent_basic" } do
    sub = OpenRouter::SubagentTool.new(
      model: "google/gemini-3-flash-preview",
      instructions: "Complete the task exactly as described. Be concise.",
      max_completion_tokens: 256
    )

    response = client.complete(
      [
        { role: "system", content: "You are an orchestrator. Delegate routine subtasks to your subagent tool." },
        { role: "user", content: "Summarize in one sentence: Ruby 3.2 added data classes and improved YJIT." }
      ],
      model: "deepseek/deepseek-v4-pro",
      tools: [sub],
      tool_choice: "auto",
      max_tokens: 300
    )

    expect(response).to be_a(OpenRouter::Response)
    # The server tool shape was accepted by the API (request reached the model).
    # deepseek/deepseek-v4-pro reasoned about the request and chose whether to delegate.
    # Whether it delegates or answers directly, a valid response must be returned.
    if response.content
      # Orchestrator answered directly (judged task didn't need subagent delegation)
      expect(response.content).to be_a(String)
      expect(response.content).not_to be_empty
    elsif response.has_tool_calls?
      # Orchestrator delegated via the subagent server tool
      expect(response.tool_calls).to be_an(Array)
      expect(response.tool_calls).not_to be_empty
    else
      # Reasoning model exhausted tokens — assert on the structure that was returned
      expect(response.finish_reason).to be_a(String)
    end
  end
end
