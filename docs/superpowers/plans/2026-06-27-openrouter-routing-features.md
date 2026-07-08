# OpenRouter Routing & Delegation Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class, validated, ergonomic access to OpenRouter's Fusion, Subagent server tool, and Pareto Code Router features in the `open_router_enhanced` gem.

**Architecture:** A thin ergonomic + validation layer on top of the existing `complete()` pipeline. A `Routing` mixin adds `fuse`/`pareto_complete` (which build `model:` + `plugins:` and delegate to `complete`); a `SubagentTool < Tool` subclass emits the `openrouter:subagent` server-tool shape; `Response#selected_model` exposes the resolved model. No changes to `complete()`'s core flow.

**Tech Stack:** Ruby ≥ 3.2, RSpec, VCR + WebMock, Faraday. Spec/design at `docs/superpowers/specs/2026-06-27-openrouter-routing-features-design.md`.

## Global Constraints

- Ruby `>= 3.2.0`; do not add new runtime dependencies.
- Module namespace is `OpenRouter`; gem name `open_router_enhanced`.
- Files use `# frozen_string_literal: true`.
- Fail-fast validation raises `ArgumentError` **before** any HTTP call.
- VCR cassettes: record with `VCR_RECORD_NEW=1` only (never delete-and-rerecord — shared mutable on-disk model cache per project memory). Cassette dir: `spec/fixtures/vcr_cassettes/`. Default match: `method uri body`.
- VCR integration recordings MUST use **cheap models only** (never the most expensive frontier models). Suggested cheap slugs below; if a slug is unavailable at record time, swap for another cheap/free model and update the spec's expected request body to match.
- Server-tool shape for subagent: `{ type: "openrouter:subagent", parameters: {...} }` (no `function` key).
- Plugin id strings: Fusion = `"fusion"`, Pareto = `"pareto-router"`. Router model aliases: `"openrouter/fusion"`, `"openrouter/pareto-code"`.

---

### Task 1: `SubagentTool` server-tool class

**Files:**
- Create: `lib/open_router/subagent_tool.rb`
- Modify: `lib/open_router.rb` (add require after line 21 `require_relative "open_router/tool"`)
- Test: `spec/subagent_tool_spec.rb`

**Interfaces:**
- Consumes: `OpenRouter::Tool` (base class).
- Produces: `OpenRouter::SubagentTool.new(model:, instructions: nil, max_completion_tokens: nil, temperature: nil, reasoning: nil)` with `#to_h => { type: "openrouter:subagent", parameters: {model:, ...}.compact }`. It is a `Tool`, so `serialize_tools` treats it via the `when Tool` branch.

- [ ] **Step 1: Write the failing test**

Create `spec/subagent_tool_spec.rb`:

```ruby
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
    it "raises ArgumentError when model is missing" do
      expect { described_class.new(instructions: "hi") }
        .to raise_error(ArgumentError, /model is required/)
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
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/subagent_tool_spec.rb`
Expected: FAIL with `uninitialized constant OpenRouter::SubagentTool`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/open_router/subagent_tool.rb`:

```ruby
# frozen_string_literal: true

require_relative "tool"

module OpenRouter
  # Represents the `openrouter:subagent` server tool, which lets an orchestrator
  # model delegate self-contained subtasks to a cheaper worker model mid-generation.
  #
  # Unlike a function Tool, it serializes to the server-tool shape:
  #   { type: "openrouter:subagent", parameters: { model:, instructions:, ... } }
  #
  # @example
  #   sub = OpenRouter::SubagentTool.new(model: "z-ai/glm-5.2", instructions: "Be concise.")
  #   client.complete(messages, model: "anthropic/claude-3.5-sonnet", tools: [sub])
  class SubagentTool < Tool
    SERVER_TOOL_TYPE = "openrouter:subagent"

    def initialize(model:, instructions: nil, max_completion_tokens: nil,
                   temperature: nil, reasoning: nil)
      raise ArgumentError, "model is required for SubagentTool" if model.nil? || model.to_s.strip.empty?

      @type = SERVER_TOOL_TYPE
      @parameters_config = {
        model: model,
        instructions: instructions,
        max_completion_tokens: max_completion_tokens,
        temperature: temperature,
        reasoning: reasoning
      }.compact
      # Intentionally skip Tool#validate_definition! (no function name/description).
    end

    def to_h
      { type: @type, parameters: @parameters_config }
    end

    def name
      @type
    end

    def description
      "OpenRouter subagent server tool (worker: #{@parameters_config[:model]})"
    end
  end
end
```

Add the require to `lib/open_router.rb` immediately after the `tool` require (line 21):

```ruby
require_relative "open_router/tool"
require_relative "open_router/subagent_tool"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/subagent_tool_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 5: Verify it serializes through `complete` (hermetic, mocked post)**

Append to `spec/subagent_tool_spec.rb` inside the top-level describe:

```ruby
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
```

Run: `bundle exec rspec spec/subagent_tool_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 6: Commit**

```bash
git add lib/open_router/subagent_tool.rb lib/open_router.rb spec/subagent_tool_spec.rb
git commit -m "feat: add SubagentTool for openrouter:subagent server tool"
```

---

### Task 2: `Routing` mixin with `pareto_complete`

**Files:**
- Create: `lib/open_router/routing.rb`
- Modify: `lib/open_router.rb` (add require before `client` require at line 33)
- Modify: `lib/open_router/client.rb` (require_relative + include the mixin)
- Test: `spec/routing_spec.rb`

**Interfaces:**
- Consumes: `Client#complete(messages, options = nil, **kwargs)`.
- Produces: `Client#pareto_complete(messages, min_coding_score: nil, **opts)` → delegates to `complete` with `model: "openrouter/pareto-code"` and a merged `pareto-router` plugin. Constants `OpenRouter::Routing::PARETO_CODE_MODEL` and `FUSION_MODEL`. Private helper `merge_plugin(opts_or_kwargs, plugin)` (used by Task 3 too).

- [ ] **Step 1: Write the failing test**

Create `spec/routing_spec.rb`:

```ruby
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
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/routing_spec.rb`
Expected: FAIL with `uninitialized constant OpenRouter::Routing` (or `undefined method pareto_complete`).

- [ ] **Step 3: Write minimal implementation**

Create `lib/open_router/routing.rb`:

```ruby
# frozen_string_literal: true

module OpenRouter
  # Mixin providing ergonomic access to OpenRouter router/meta-model features
  # (Fusion, Pareto Code Router). Builds the right model alias + plugin config
  # and delegates to Client#complete.
  module Routing
    FUSION_MODEL = "openrouter/fusion"
    PARETO_CODE_MODEL = "openrouter/pareto-code"

    # Route to the cheapest code-capable model meeting a quality bar.
    #
    # @param min_coding_score [Float, nil] 0.0–1.0 (1.0 = best). Optional.
    def pareto_complete(messages, min_coding_score: nil, **opts)
      validate_min_coding_score!(min_coding_score)

      plugin = { id: "pareto-router" }
      plugin[:min_coding_score] = min_coding_score unless min_coding_score.nil?

      kwargs = merge_plugin(opts, plugin)
      complete(messages, model: PARETO_CODE_MODEL, **kwargs)
    end

    private

    def validate_min_coding_score!(score)
      return if score.nil?

      unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
        raise ArgumentError, "min_coding_score must be a number between 0.0 and 1.0 (got #{score.inspect})"
      end
    end

    # Merge a router plugin into any caller-supplied plugins, de-duped by :id.
    def merge_plugin(opts, plugin)
      existing = Array(opts[:plugins]).map { |p| p.transform_keys(&:to_sym) }
      existing = existing.reject { |p| p[:id].to_s == plugin[:id].to_s }
      opts.merge(plugins: existing + [plugin])
    end
  end
end
```

Add require to `lib/open_router.rb` immediately before the `client` require (line 33):

```ruby
require_relative "open_router/routing"
require_relative "open_router/client"
```

Modify `lib/open_router/client.rb` — add the require near the other mixin requires (after line 10 `require_relative "request_handler"`):

```ruby
require_relative "request_handler"
require_relative "routing"
```

And add the include in the `Client` class body (after line 20 `include OpenRouter::RequestHandler`):

```ruby
    include OpenRouter::RequestHandler
    include OpenRouter::Routing
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/routing_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/open_router/routing.rb lib/open_router/client.rb lib/open_router.rb spec/routing_spec.rb
git commit -m "feat: add Routing mixin with pareto_complete"
```

---

### Task 3: `fuse` (Fusion) on the `Routing` mixin

**Files:**
- Modify: `lib/open_router/routing.rb`
- Test: `spec/routing_spec.rb`

**Interfaces:**
- Consumes: `Client#complete`, `Routing#merge_plugin` (from Task 2).
- Produces: `Client#fuse(messages, analysis_models: nil, judge: nil, preset: nil, max_tool_calls: nil, **opts)` → delegates to `complete` with `model: "openrouter/fusion"` and a merged `fusion` plugin `{ id: "fusion", analysis_models:, model: judge, preset:, max_tool_calls: }.compact`.

- [ ] **Step 1: Write the failing test**

Append a new describe block to `spec/routing_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/routing_spec.rb -e "#fuse"`
Expected: FAIL with `undefined method 'fuse'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/open_router/routing.rb`, add `fuse` above the `private` keyword (after `pareto_complete`):

```ruby
    # Fan a prompt out to a panel of models and synthesize one answer.
    # NOTE: Fusion costs ~4–5x a single completion (panel calls + judge).
    #
    # @param analysis_models [Array<String>, nil] 1–8 panel model ids.
    # @param judge [String, nil] synthesis model id (defaults to the fusion model server-side).
    # @param preset [String, Symbol, nil] curated panel slug (e.g. "general-budget").
    # @param max_tool_calls [Integer, nil] 1–16.
    def fuse(messages, analysis_models: nil, judge: nil, preset: nil, max_tool_calls: nil, **opts)
      validate_analysis_models!(analysis_models)
      validate_max_tool_calls!(max_tool_calls)

      plugin = {
        id: "fusion",
        analysis_models: analysis_models,
        model: judge,
        preset: preset&.to_s,
        max_tool_calls: max_tool_calls
      }.compact

      kwargs = merge_plugin(opts, plugin)
      complete(messages, model: FUSION_MODEL, **kwargs)
    end
```

And add these validators in the `private` section (after `validate_min_coding_score!`):

```ruby
    def validate_analysis_models!(models)
      return if models.nil?

      unless models.is_a?(Array) && (1..8).cover?(models.size) && models.all? { |m| m.is_a?(String) && !m.strip.empty? }
        raise ArgumentError, "analysis_models must be an array of 1–8 model id strings (got #{models.inspect})"
      end
    end

    def validate_max_tool_calls!(value)
      return if value.nil?

      unless value.is_a?(Integer) && (1..16).cover?(value)
        raise ArgumentError, "max_tool_calls must be an integer between 1 and 16 (got #{value.inspect})"
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/routing_spec.rb`
Expected: PASS (11 examples total).

- [ ] **Step 5: Commit**

```bash
git add lib/open_router/routing.rb spec/routing_spec.rb
git commit -m "feat: add fuse for OpenRouter Fusion router"
```

---

### Task 4: `Response#selected_model`

**Files:**
- Modify: `lib/open_router/response.rb`
- Test: `spec/response_selected_model_spec.rb`

**Interfaces:**
- Consumes: `Response#raw_response` (indifferent-access hash).
- Produces: `Response#selected_model` → `String, nil` (the resolved `model` field from the API response).

- [ ] **Step 1: Write the failing test**

Create `spec/response_selected_model_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::Response do
  describe "#selected_model" do
    it "returns the model the router actually resolved" do
      response = described_class.new(
        "model" => "anthropic/claude-3.5-sonnet",
        "choices" => [{ "message" => { "role" => "assistant", "content" => "hi" } }]
      )
      expect(response.selected_model).to eq("anthropic/claude-3.5-sonnet")
    end

    it "returns nil when the response has no model field" do
      response = described_class.new("choices" => [])
      expect(response.selected_model).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/response_selected_model_spec.rb`
Expected: FAIL with `undefined method 'selected_model'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/open_router/response.rb`, add this method after the `keys` method (near the other delegators, before `# Tool calling methods`):

```ruby
    # The concrete model the API/router actually used for this response.
    # Useful for Pareto, Auto, and Fusion routing ("which model answered?").
    #
    # @return [String, nil]
    def selected_model
      @raw_response["model"]
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/response_selected_model_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/open_router/response.rb spec/response_selected_model_spec.rb
git commit -m "feat: add Response#selected_model for resolved router model"
```

---

### Task 5: VCR integration — Pareto Code Router (happy + real error)

**Files:**
- Create: `spec/vcr/pareto_spec.rb`
- Create (recorded): `spec/fixtures/vcr_cassettes/pareto_basic.yml`, `spec/fixtures/vcr_cassettes/pareto_error.yml`

**Interfaces:**
- Consumes: `Client#pareto_complete`, `Response#selected_model`, `OpenRouter::ServerError`.

- [ ] **Step 1: Write the failing test**

Create `spec/vcr/pareto_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Pareto Code Router", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }
  let(:messages) { [{ role: "user", content: "Write a Ruby method that merges two sorted arrays." }] }

  it "routes to the cheapest code-capable model meeting the score",
     vcr: { cassette_name: "pareto_basic" } do
    response = client.pareto_complete(messages, min_coding_score: 0.5, max_tokens: 200)

    expect(response).to be_a(OpenRouter::Response)
    expect(response.content).to be_a(String)
    expect(response.content).not_to be_empty
    # The router resolves to a concrete model, surfaced via selected_model.
    expect(response.selected_model).to be_a(String)
    expect(response.selected_model).not_to eq("openrouter/pareto-code")
  end

  it "propagates a real API error for an invalid request",
     vcr: { cassette_name: "pareto_error" } do
    # Bypass client-side validation to capture genuine server-side rejection:
    # a malformed pareto-router plugin value the API rejects.
    expect do
      client.complete(
        messages,
        model: "openrouter/pareto-code",
        plugins: [{ id: "pareto-router", min_coding_score: "definitely-not-a-number" }],
        max_tokens: 50
      )
    end.to raise_error(OpenRouter::ServerError)
  end
end
```

- [ ] **Step 2: Run test to verify it fails (no cassette yet)**

Run: `bundle exec rspec spec/vcr/pareto_spec.rb`
Expected: FAIL — VCR raises because no cassette exists and default record mode `:once` will try a live call without a key in CI, or (locally) records. To control recording explicitly, proceed to Step 3.

- [ ] **Step 3: Record the cassettes against the live API (cheap model)**

Run (requires `OPENROUTER_API_KEY` in env / `.env`):

```bash
VCR_RECORD_NEW=1 bundle exec rspec spec/vcr/pareto_spec.rb
```

Then inspect `spec/fixtures/vcr_cassettes/pareto_basic.yml`:
- Confirm the recorded **request body** contains `"plugins":[{"id":"pareto-router","min_coding_score":0.5}]` and `"model":"openrouter/pareto-code"`.
- If the live API expects `min_coding_score` elsewhere (e.g. top-level) or a different plugin id, update `lib/open_router/routing.rb` and the Task 2 unit spec to match reality, re-run unit specs green, then re-record with `VCR_RECORD_NEW=1`.
- Confirm `pareto_error.yml` recorded a non-2xx response that the gem maps to `ServerError`. If the gem returns a 200 with an error body instead, adjust the test expectation to assert on the error surfaced in the response per the gem's actual error handling (check `request_handler.rb`), keeping the assertion truthful to recorded behavior.

- [ ] **Step 4: Replay to verify green (cassette mode)**

Run: `CI=true bundle exec rspec spec/vcr/pareto_spec.rb`
Expected: PASS (2 examples), replaying cassettes with record mode `:none`.

- [ ] **Step 5: Commit**

```bash
git add spec/vcr/pareto_spec.rb spec/fixtures/vcr_cassettes/pareto_basic.yml spec/fixtures/vcr_cassettes/pareto_error.yml
git commit -m "test: VCR integration for pareto_complete (happy + error)"
```

---

### Task 6: VCR integration — Subagent server tool

**Files:**
- Create: `spec/vcr/subagent_spec.rb`
- Create (recorded): `spec/fixtures/vcr_cassettes/subagent_basic.yml`

**Interfaces:**
- Consumes: `OpenRouter::SubagentTool`, `Client#complete`.

- [ ] **Step 1: Write the failing test**

Create `spec/vcr/subagent_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Subagent server tool", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

  it "lets an orchestrator delegate to a cheap worker model",
     vcr: { cassette_name: "subagent_basic" } do
    sub = OpenRouter::SubagentTool.new(
      model: "deepseek/deepseek-chat",
      instructions: "Complete the task exactly as described. Be concise.",
      max_completion_tokens: 256
    )

    response = client.complete(
      [
        { role: "system", content: "You are an orchestrator. Delegate routine subtasks to your subagent tool." },
        { role: "user", content: "Summarize in one sentence: Ruby 3.2 added data classes and improved YJIT." }
      ],
      # Use a cheap orchestrator too; it must support tool calling.
      model: "openai/gpt-4o-mini",
      tools: [sub],
      tool_choice: "auto",
      max_tokens: 300
    )

    expect(response).to be_a(OpenRouter::Response)
    expect(response.content).to be_a(String)
    expect(response.content).not_to be_empty
  end
end
```

- [ ] **Step 2: Run test to verify it fails (no cassette)**

Run: `bundle exec rspec spec/vcr/subagent_spec.rb`
Expected: FAIL — no cassette recorded yet.

- [ ] **Step 3: Record against the live API (cheap orchestrator + worker)**

Run:

```bash
VCR_RECORD_NEW=1 bundle exec rspec spec/vcr/subagent_spec.rb
```

Inspect `spec/fixtures/vcr_cassettes/subagent_basic.yml`:
- Confirm the request body `tools` array contains `{"type":"openrouter:subagent","parameters":{"model":"deepseek/deepseek-chat",...}}`.
- If the live API rejects the orchestrator model for server tools or names the parameters differently, adjust `lib/open_router/subagent_tool.rb` + the Task 1 unit spec to match, re-run unit specs green, then re-record.
- If the chosen cheap models are unavailable, swap for other cheap/free models and update the spec + re-record.

- [ ] **Step 4: Replay to verify green**

Run: `CI=true bundle exec rspec spec/vcr/subagent_spec.rb`
Expected: PASS (1 example).

- [ ] **Step 5: Commit**

```bash
git add spec/vcr/subagent_spec.rb spec/fixtures/vcr_cassettes/subagent_basic.yml
git commit -m "test: VCR integration for SubagentTool delegation"
```

---

### Task 7: VCR integration — Fusion (cheap panel)

**Files:**
- Create: `spec/vcr/fusion_spec.rb`
- Create (recorded): `spec/fixtures/vcr_cassettes/fusion_basic.yml`

**Interfaces:**
- Consumes: `Client#fuse`, `Response#selected_model`.

- [ ] **Step 1: Write the failing test**

Create `spec/vcr/fusion_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Fusion router", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }
  let(:messages) { [{ role: "user", content: "In one short paragraph, what is the CAP theorem?" }] }

  it "fuses a budget panel into a single synthesized answer",
     vcr: { cassette_name: "fusion_basic" } do
    response = client.fuse(
      messages,
      # Cheap panel + cheap judge — never frontier models.
      analysis_models: ["deepseek/deepseek-chat", "google/gemini-flash-1.5"],
      judge: "deepseek/deepseek-chat",
      max_tokens: 300
    )

    expect(response).to be_a(OpenRouter::Response)
    expect(response.content).to be_a(String)
    expect(response.content).not_to be_empty
  end
end
```

- [ ] **Step 2: Run test to verify it fails (no cassette)**

Run: `bundle exec rspec spec/vcr/fusion_spec.rb`
Expected: FAIL — no cassette recorded yet.

- [ ] **Step 3: Record against the live API (cheap panel — note ~4–5x cost)**

Run:

```bash
VCR_RECORD_NEW=1 bundle exec rspec spec/vcr/fusion_spec.rb
```

Inspect `spec/fixtures/vcr_cassettes/fusion_basic.yml`:
- Confirm request body `plugins` contains `{"id":"fusion","analysis_models":[...],"model":"deepseek/deepseek-chat"}`.
- **Pin the flagged field name:** if the live API uses `models` instead of `analysis_models` (or a different judge key), update `lib/open_router/routing.rb`'s `fuse` plugin hash + the Task 3 unit spec to match, re-run unit specs green, then re-record.
- Keep `max_tokens` modest to bound cost.

- [ ] **Step 4: Replay to verify green**

Run: `CI=true bundle exec rspec spec/vcr/fusion_spec.rb`
Expected: PASS (1 example).

- [ ] **Step 5: Commit**

```bash
git add spec/vcr/fusion_spec.rb spec/fixtures/vcr_cassettes/fusion_basic.yml
git commit -m "test: VCR integration for fuse (Fusion router, budget panel)"
```

---

### Task 8: Docs + version bump to 2.2.0

**Files:**
- Modify: `lib/open_router/version.rb`
- Modify: `README.md` (add a "Routing & Delegation" section)
- Modify: `CHANGELOG.md` if present (check first; create entry under a new `## 2.2.0` heading only if the file exists)

**Interfaces:** none (release task).

- [ ] **Step 1: Confirm the full suite is green first**

Run: `CI=true bundle exec rspec`
Expected: PASS (entire suite, cassettes replayed in `:none` mode). Fix any failures before bumping.

- [ ] **Step 2: Run the linter**

Run: `bundle exec rubocop lib/open_router/routing.rb lib/open_router/subagent_tool.rb lib/open_router/response.rb`
Expected: no offenses (auto-correct with `-a` if safe, re-run specs after).

- [ ] **Step 3: Bump the version**

Edit `lib/open_router/version.rb` — change the version constant to `"2.2.0"`.

- [ ] **Step 4: Add README usage section**

Add to `README.md` (under existing feature docs) — show real usage and the fusion cost note:

```markdown
## Routing & Delegation

### Fusion — multi-model synthesis
```ruby
# Fan out to a budget panel and synthesize one answer.
# Note: Fusion costs ~4–5x a single completion (panel + judge).
response = client.fuse(messages,
  analysis_models: ["deepseek/deepseek-chat", "google/gemini-flash-1.5"],
  judge: "deepseek/deepseek-chat")
response.selected_model # => the model that produced the synthesis
```

### Pareto Code Router — cheapest model over a quality bar
```ruby
response = client.pareto_complete(messages, min_coding_score: 0.8)
response.selected_model # => e.g. "anthropic/claude-3.5-sonnet"
```

### Subagent — delegate subtasks to a cheaper worker
```ruby
sub = OpenRouter::SubagentTool.new(model: "deepseek/deepseek-chat",
                                   instructions: "Be concise.")
response = client.complete(messages,
  model: "openai/gpt-4o-mini", tools: [sub], tool_choice: "auto")
```

All three raise `ArgumentError` on invalid arguments and surface API errors via the
standard error handling / `:on_error` callback.
```

- [ ] **Step 5: Commit**

```bash
git add lib/open_router/version.rb README.md
git commit -m "chore: docs + bump version to 2.2.0 for routing features"
```

---

## Self-Review

**Spec coverage:**
- Fusion → Task 3 (`fuse`) + Task 7 (VCR). ✓
- Subagent → Task 1 (`SubagentTool`) + Task 6 (VCR). ✓
- Pareto → Task 2 (`pareto_complete`) + Task 5 (VCR). ✓
- `selected_model` → Task 4. ✓
- Validation / fail-fast → Tasks 1, 2, 3 (ArgumentError specs). ✓
- Error handling (real API error) → Task 5 (`pareto_error` cassette). ✓
- Plugin merge (no clobber) → Task 2. ✓
- Cheap models for cassettes → Tasks 5–7 (explicit). ✓
- Version bump + docs → Task 8. ✓
- Field-name uncertainty (`analysis_models`, `min_coding_score` placement) → record-and-reconcile steps in Tasks 5 & 7. ✓

**Placeholder scan:** No TBD/TODO; all code shown in full; cassette "swap if unavailable" instructions are real recording guidance, not placeholders.

**Type consistency:** `pareto_complete`, `fuse`, `SubagentTool#to_h`, `Response#selected_model`, `merge_plugin`, `FUSION_MODEL`/`PARETO_CODE_MODEL` used consistently across tasks. `merge_plugin` defined in Task 2, reused in Task 3. ✓
