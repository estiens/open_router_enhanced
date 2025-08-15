# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::UsageTracker do
  let(:tracker) { described_class.new }

  describe "initialization" do
    it "initializes with zero values" do
      expect(tracker.total_prompt_tokens).to eq(0)
      expect(tracker.total_completion_tokens).to eq(0)
      expect(tracker.total_cached_tokens).to eq(0)
      expect(tracker.total_cost).to eq(0.0)
      expect(tracker.request_count).to eq(0)
    end

    it "records session start time" do
      expect(tracker.session_start).to be_a(Time)
      expect(tracker.session_start).to be <= Time.now
    end
  end

  describe "#track" do
    let(:mock_response) do
      double("Response",
             model: "openai/gpt-4o-mini",
             prompt_tokens: 100,
             completion_tokens: 50,
             cached_tokens: 10,
             cost_estimate: 0.002,
             id: "test-123")
    end

    it "updates token counts" do
      tracker.track(mock_response)

      expect(tracker.total_prompt_tokens).to eq(100)
      expect(tracker.total_completion_tokens).to eq(50)
      expect(tracker.total_cached_tokens).to eq(10)
    end

    it "updates cost and request count" do
      tracker.track(mock_response)

      expect(tracker.total_cost).to eq(0.002)
      expect(tracker.request_count).to eq(1)
    end

    it "tracks per-model statistics" do
      tracker.track(mock_response)

      model_stats = tracker.model_usage["openai/gpt-4o-mini"]
      expect(model_stats[:prompt_tokens]).to eq(100)
      expect(model_stats[:completion_tokens]).to eq(50)
      expect(model_stats[:cached_tokens]).to eq(10)
      expect(model_stats[:cost]).to eq(0.002)
      expect(model_stats[:requests]).to eq(1)
    end

    it "accumulates multiple responses" do
      response2 = double("Response",
                         model: "openai/gpt-4o-mini",
                         prompt_tokens: 80,
                         completion_tokens: 30,
                         cached_tokens: 5,
                         cost_estimate: 0.001,
                         id: "test-456")

      tracker.track(mock_response)
      tracker.track(response2)

      expect(tracker.total_prompt_tokens).to eq(180)
      expect(tracker.total_completion_tokens).to eq(80)
      expect(tracker.total_cached_tokens).to eq(15)
      expect(tracker.total_cost).to eq(0.003)
      expect(tracker.request_count).to eq(2)
    end

    it "handles responses without cost estimates" do
      response_no_cost = double("Response",
                                model: "openai/gpt-4o-mini",
                                prompt_tokens: 100,
                                completion_tokens: 50,
                                cached_tokens: 10,
                                cost_estimate: nil,
                                id: "test-789")

      # Mock ModelRegistry for cost estimation
      allow(OpenRouter::ModelRegistry).to receive(:get_model).and_return({
                                                                           "pricing" => { "prompt" => "0.001",
                                                                                          "completion" => "0.002" }
                                                                         })

      tracker.track(response_no_cost)

      # Should estimate: (100/1_000_000 * 0.001) + (50/1_000_000 * 0.002) = 0.0000002
      expect(tracker.total_cost).to be_within(0.0000001).of(0.0000002)
    end

    it "handles nil responses gracefully" do
      expect { tracker.track(nil) }.not_to raise_error
      expect(tracker.request_count).to eq(0)
    end
  end

  describe "calculated properties" do
    before do
      response1 = double("Response",
                         model: "openai/gpt-4o-mini", prompt_tokens: 100, completion_tokens: 50,
                         cached_tokens: 10, cost_estimate: 0.002, id: "test-1")
      response2 = double("Response",
                         model: "anthropic/claude-3-haiku", prompt_tokens: 150, completion_tokens: 75,
                         cached_tokens: 20, cost_estimate: 0.003, id: "test-2")

      tracker.track(response1)
      tracker.track(response2)
    end

    describe "#total_tokens" do
      it "returns sum of prompt and completion tokens" do
        expect(tracker.total_tokens).to eq(375) # 250 + 125
      end
    end

    describe "#average_tokens_per_request" do
      it "calculates average tokens per request" do
        expect(tracker.average_tokens_per_request).to eq(187.5)
      end

      it "handles zero requests" do
        empty_tracker = described_class.new
        expect(empty_tracker.average_tokens_per_request).to eq(0)
      end
    end

    describe "#average_cost_per_request" do
      it "calculates average cost per request" do
        expect(tracker.average_cost_per_request).to eq(0.0025)
      end
    end

    describe "#cache_hit_rate" do
      it "calculates cache hit rate percentage" do
        # 30 cached / 250 prompt * 100 = 12%
        expect(tracker.cache_hit_rate).to eq(12.0)
      end

      it "handles zero prompt tokens" do
        empty_tracker = described_class.new
        expect(empty_tracker.cache_hit_rate).to eq(0)
      end
    end

    describe "#most_used_model" do
      it "returns model with most requests" do
        # Add another request for one model
        response3 = double("Response",
                           model: "openai/gpt-4o-mini", prompt_tokens: 50, completion_tokens: 25,
                           cached_tokens: 5, cost_estimate: 0.001, id: "test-3")
        tracker.track(response3)

        expect(tracker.most_used_model).to eq("openai/gpt-4o-mini")
      end
    end

    describe "#most_expensive_model" do
      it "returns model with highest total cost" do
        expect(tracker.most_expensive_model).to eq("anthropic/claude-3-haiku")
      end
    end
  end

  describe "#reset!" do
    before do
      response = double("Response",
                        model: "openai/gpt-4o-mini", prompt_tokens: 100, completion_tokens: 50,
                        cached_tokens: 10, cost_estimate: 0.002, id: "test-reset")
      tracker.track(response)
    end

    it "resets all counters to zero" do
      tracker.reset!

      expect(tracker.total_prompt_tokens).to eq(0)
      expect(tracker.total_completion_tokens).to eq(0)
      expect(tracker.total_cached_tokens).to eq(0)
      expect(tracker.total_cost).to eq(0.0)
      expect(tracker.request_count).to eq(0)
    end

    it "clears model usage data" do
      tracker.reset!
      expect(tracker.model_usage).to be_empty
    end

    it "updates session start time" do
      old_start = tracker.session_start
      sleep(0.01) # Ensure time difference
      tracker.reset!

      expect(tracker.session_start).to be > old_start
    end
  end

  describe "#summary" do
    before do
      response = double("Response",
                        model: "openai/gpt-4o-mini", prompt_tokens: 100, completion_tokens: 50,
                        cached_tokens: 10, cost_estimate: 0.002, id: "test-summary")
      tracker.track(response)
    end

    it "returns comprehensive summary hash" do
      summary = tracker.summary

      expect(summary).to have_key(:session)
      expect(summary).to have_key(:tokens)
      expect(summary).to have_key(:cost)
      expect(summary).to have_key(:performance)
      expect(summary).to have_key(:models)
    end

    it "includes session information" do
      summary = tracker.summary
      session = summary[:session]

      expect(session[:start]).to eq(tracker.session_start)
      expect(session[:requests]).to eq(1)
      expect(session[:duration_seconds]).to be > 0
    end

    it "includes token breakdown" do
      summary = tracker.summary
      tokens = summary[:tokens]

      expect(tokens[:total]).to eq(150)
      expect(tokens[:prompt]).to eq(100)
      expect(tokens[:completion]).to eq(50)
      expect(tokens[:cached]).to eq(10)
      expect(tokens[:cache_hit_rate]).to eq("10.0%")
    end

    it "includes cost information" do
      summary = tracker.summary
      cost = summary[:cost]

      expect(cost[:total]).to eq(0.002)
      expect(cost[:average_per_request]).to eq(0.002)
    end

    it "includes model breakdown" do
      summary = tracker.summary
      models = summary[:models]

      expect(models[:most_used]).to eq("openai/gpt-4o-mini")
      expect(models[:breakdown]).to have_key("openai/gpt-4o-mini")
    end
  end

  describe "#export_csv" do
    before do
      response1 = double("Response",
                         model: "openai/gpt-4o-mini", prompt_tokens: 100, completion_tokens: 50,
                         cached_tokens: 10, cost_estimate: 0.002, id: "test-1")
      response2 = double("Response",
                         model: "anthropic/claude-3-haiku", prompt_tokens: 150, completion_tokens: 75,
                         cached_tokens: 20, cost_estimate: 0.003, id: "test-2")

      tracker.track(response1)
      tracker.track(response2)
    end

    it "exports usage history as CSV" do
      csv_data = tracker.export_csv

      lines = csv_data.split("\n")
      expect(lines.length).to eq(3) # Header + 2 data rows

      # Check header
      expect(lines[0]).to include("Timestamp,Model,Prompt Tokens")

      # Check data rows
      expect(lines[1]).to include("openai/gpt-4o-mini,100,50,10,0.002,test-1")
      expect(lines[2]).to include("anthropic/claude-3-haiku,150,75,20,0.003,test-2")
    end
  end

  describe "#history" do
    before do
      3.times do |i|
        response = double("Response",
                          model: "openai/gpt-4o-mini", prompt_tokens: 100, completion_tokens: 50,
                          cached_tokens: 10, cost_estimate: 0.002, id: "test-#{i}")
        tracker.track(response)
      end
    end

    it "returns all history by default" do
      history = tracker.history
      expect(history.length).to eq(3)
    end

    it "limits history when requested" do
      history = tracker.history(limit: 2)
      expect(history.length).to eq(2)
      expect(history.last[:response_id]).to eq("test-2")
    end
  end
end
