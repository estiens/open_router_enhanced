# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Prompt Templates", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  describe "basic prompt templates" do
    it "uses simple variable interpolation", vcr: { cassette_name: "prompt_template_basic" } do
      template = OpenRouter::PromptTemplate.new(
        template: "Hello {name}, welcome to {location}!",
        input_variables: %i[name location]
      )

      prompt = template.format(name: "Alice", location: "San Francisco")
      expect(prompt).to eq("Hello Alice, welcome to San Francisco!")

      response = client.complete(
        [{ role: "user", content: prompt }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).not_to be_empty
    end

    it "handles multi-line templates", vcr: { cassette_name: "prompt_template_multiline" } do
      template = OpenRouter::PromptTemplate.new(
        template: <<~TEMPLATE,
          You are a {role} assistant.

          Task: {task}
          Context: {context}

          Please provide a helpful response.
        TEMPLATE
        input_variables: %i[role task context]
      )

      prompt = template.format(
        role: "helpful",
        task: "explain quantum computing",
        context: "beginner audience"
      )

      response = client.complete(
        [{ role: "system", content: prompt }, { role: "user", content: "Explain quantum computing" }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 150 }
      )

      expect(response.content.downcase).to include("quantum")
    end
  end

  describe "few-shot prompt templates" do
    it "creates few-shot examples", vcr: { cassette_name: "prompt_template_few_shot" } do
      template = OpenRouter::PromptTemplate.new(
        prefix: "You are a sentiment analyzer. Classify text as positive, negative, or neutral. Here are examples:",
        examples: [
          { input: "I love this product!", output: "positive" },
          { input: "This is terrible.", output: "negative" },
          { input: "It's okay, nothing special.", output: "neutral" }
        ],
        example_template: "Input: {input}\nOutput: {output}",
        suffix: "Input: {text}\nOutput:",
        input_variables: [:text]
      )

      messages = template.to_messages(text: "This is amazing!")

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 10 }
      )

      expect(messages).to be_an(Array)
      expect(messages.first[:role]).to eq("user")
      expect(response.content.downcase).to include("positive")
    end

    it "handles complex few-shot patterns", vcr: { cassette_name: "prompt_template_complex_few_shot" } do
      template = OpenRouter::PromptTemplate.new(
        prefix: "You are a code translator. Convert Python to JavaScript. Examples:",
        examples: [
          {
            input: "print('Hello World')",
            output: "console.log('Hello World');"
          },
          {
            input: "x = [1, 2, 3]\nfor i in x:\n    print(i)",
            output: "const x = [1, 2, 3];\nfor (const i of x) {\n    console.log(i);\n}"
          }
        ],
        example_template: "Python: {input}\nJavaScript: {output}",
        suffix: "Convert this Python code: {code}",
        input_variables: [:code]
      )

      messages = template.to_messages(code: "def greet(name):\n    return f'Hello {name}'")

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 200 }
      )

      expect(response.content).to include("function")
      expect(response.content).to include("greet")
    end
  end

  describe "chat formatting templates" do
    it "formats multi-turn conversations with role markers", vcr: { cassette_name: "prompt_template_chat_format" } do
      template = OpenRouter::PromptTemplate.new(
        template: <<~TEMPLATE,
          System: You are a {role} assistant specializing in {specialty}.

          User: {user_message_1}

          Assistant: {assistant_response_1}

          User: {user_message_2}
        TEMPLATE
        input_variables: %i[role specialty user_message_1 assistant_response_1 user_message_2]
      )

      messages = template.to_messages(
        role: "helpful",
        specialty: "programming",
        user_message_1: "What is Python?",
        assistant_response_1: "Python is a programming language known for its simplicity.",
        user_message_2: "Can you show me a Hello World example?"
      )

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 100 }
      )

      expect(messages.length).to eq(4) # system + user + assistant + user
      expect(messages[0][:role]).to eq("system")
      expect(messages[1][:role]).to eq("user")
      expect(messages[2][:role]).to eq("assistant")
      expect(messages[3][:role]).to eq("user")
      expect(response.content).to include("print")
    end
  end

  describe "template composition" do
    it "composes multiple templates", vcr: { cassette_name: "prompt_template_composition" } do
      base_template = OpenRouter::PromptTemplate.new(
        template: "You are a {role} assistant.",
        input_variables: [:role]
      )

      task_template = OpenRouter::PromptTemplate.new(
        template: "Task: {task}\nRequirements: {requirements}",
        input_variables: %i[task requirements]
      )

      composed_prompt = [
        base_template.format(role: "technical"),
        task_template.format(
          task: "code review",
          requirements: "focus on security and performance"
        )
      ].join("\n\n")

      response = client.complete(
        [{ role: "system", content: composed_prompt }, { role: "user", content: "Review this code: print('hello')" }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 150 }
      )

      expect(composed_prompt).to include("technical assistant")
      expect(composed_prompt).to include("code review")
      expect(response.content).to include("code")
    end
  end

  describe "template with tools integration" do
    let(:calculator_tool) do
      OpenRouter::Tool.define do
        name "calculate"
        description "Perform calculations"
        parameters do
          string "expression", required: true, description: "Mathematical expression"
        end
      end
    end

    it "integrates templates with tool calling", vcr: { cassette_name: "prompt_template_with_tools" } do
      skip "VCR cassette mismatch - needs re-recording with current API"

      template = OpenRouter::PromptTemplate.new(
        template: "You are a math tutor. Help solve: {problem}. Please calculate: {expression}",
        input_variables: %i[problem expression]
      )

      messages = template.to_messages(
        problem: "basic arithmetic",
        expression: "25 * 4 + 10"
      )

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(messages[0][:content]).to include("math tutor")
      expect(messages[0][:content]).to include("25 * 4 + 10")
      expect(response).to be_a(OpenRouter::Response)
    end
  end

  describe "template with structured outputs" do
    let(:analysis_schema) do
      OpenRouter::Schema.define("analysis_result") do
        string :summary, required: true, description: "Brief summary"
        number :confidence, required: true, description: "Confidence score 0-1"
        array :key_points, items: { type: "string" }, description: "Main points"
      end
    end

    let(:response_format) do
      {
        type: "json_schema",
        json_schema: analysis_schema.to_h
      }
    end

    it "combines templates with structured outputs", vcr: { cassette_name: "prompt_template_structured" } do
      skip "VCR cassette mismatch - needs re-recording with current API"

      template = OpenRouter::PromptTemplate.new(
        template: <<~TEMPLATE,
          Analyze this {content_type}: {content}

          Provide your analysis in the requested JSON format.
          Focus on: {focus_areas}
        TEMPLATE
        input_variables: %i[content_type content focus_areas]
      )

      prompt = template.format(
        content_type: "text",
        content: "Machine learning is revolutionizing many industries by enabling automated decision-making and pattern recognition.",
        focus_areas: "key concepts and impact"
      )

      response = client.complete(
        [{ role: "user", content: prompt }],
        model: "openai/gpt-4o-mini",
        response_format: response_format,
        extras: { max_tokens: 300 }
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured).to have_key("summary")
      expect(structured).to have_key("confidence")
      expect(structured).to have_key("key_points")
    end
  end

  describe "partial templates" do
    it "creates partial templates with pre-filled variables", vcr: { cassette_name: "prompt_template_partial" } do
      template = OpenRouter::PromptTemplate.new(
        template: "Context: {context}\n\nQuestion: {question}\n\nAnswer:",
        input_variables: %i[context question]
      )

      # Create a partial with context pre-filled
      science_qa = template.partial(
        context: "Water boils at 100°C (212°F) at sea level atmospheric pressure."
      )

      # Now only need to provide the question
      prompt = science_qa.format(question: "What is the boiling point of water in Celsius?")

      response = client.complete(
        [{ role: "user", content: prompt }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(prompt).to include("Water boils at 100°C")
      expect(prompt).to include("What is the boiling point of water in Celsius?")
      expect(response.content).to include("100")
    end
  end
end
