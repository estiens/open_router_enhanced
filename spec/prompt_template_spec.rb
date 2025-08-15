# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::PromptTemplate do
  describe "basic templates" do
    it "formats simple templates with variables" do
      template = described_class.new(
        template: "Translate '{text}' to {language}",
        input_variables: %i[text language]
      )

      result = template.format(text: "Hello", language: "French")
      expect(result).to eq("Translate 'Hello' to French")
    end

    it "raises error for missing variables" do
      template = described_class.new(
        template: "Hello {name}",
        input_variables: [:name]
      )

      expect { template.format({}) }.to raise_error(ArgumentError, /Missing required variables: name/)
    end

    it "handles partial variables" do
      template = described_class.new(
        template: "Translate to {language}: {text}",
        input_variables: %i[text language],
        partial_variables: { language: "French" }
      )

      result = template.format(text: "Hello")
      expect(result).to eq("Translate to French: Hello")
    end
  end

  describe "few-shot templates" do
    let(:few_shot_template) do
      described_class.new(
        prefix: "You are a helpful translator.",
        suffix: "Now translate: {input}",
        examples: [
          { input: "Hello", output: "Bonjour" },
          { input: "Goodbye", output: "Au revoir" }
        ],
        example_template: "Input: {input}\nOutput: {output}",
        input_variables: [:input]
      )
    end

    it "formats few-shot prompts correctly" do
      result = few_shot_template.format(input: "Thank you")

      expect(result).to include("You are a helpful translator.")
      expect(result).to include("Input: Hello\nOutput: Bonjour")
      expect(result).to include("Input: Goodbye\nOutput: Au revoir")
      expect(result).to include("Now translate: Thank you")
    end

    it "identifies as few-shot template" do
      expect(few_shot_template.few_shot_template?).to be true
    end
  end

  describe "#partial" do
    it "creates a new template with partial variables" do
      original = described_class.new(
        template: "{greeting} {name}!",
        input_variables: %i[greeting name]
      )

      partial = original.partial(greeting: "Hello")

      expect(partial.input_variables).to eq([:name])
      expect(partial.format(name: "World")).to eq("Hello World!")
    end
  end

  describe "#to_messages" do
    it "converts simple template to messages array" do
      template = described_class.new(
        template: "Hello {name}",
        input_variables: [:name]
      )

      messages = template.to_messages(name: "World")
      expect(messages).to eq([{ role: "user", content: "Hello World" }])
    end

    it "parses role markers in template" do
      template = described_class.new(
        template: "System: You are a helpful assistant.\nUser: {question}",
        input_variables: [:question]
      )

      messages = template.to_messages(question: "What is 2+2?")

      expect(messages).to eq([
                               { role: "system", content: "You are a helpful assistant." },
                               { role: "user", content: "What is 2+2?" }
                             ])
    end

    it "handles multi-line role content" do
      template = described_class.new(
        template: "System: You are an expert.\nYou know many things.\nUser: {question}",
        input_variables: [:question]
      )

      messages = template.to_messages(question: "Help me")

      expect(messages[0][:content]).to eq("You are an expert.\nYou know many things.")
      expect(messages[1][:content]).to eq("Help me")
    end
  end

  describe ".build DSL" do
    it "creates template using DSL" do
      template = described_class.build do
        template "Hello {name}, welcome to {place}"
        variables :name, :place
      end

      result = template.format(name: "Alice", place: "Wonderland")
      expect(result).to eq("Hello Alice, welcome to Wonderland")
    end

    it "creates few-shot template using DSL" do
      template = described_class.build do
        prefix "Translate these examples:"
        suffix "Now: {input}"
        examples [
          { input: "cat", output: "chat" },
          { input: "dog", output: "chien" }
        ]
        example_template "{input} -> {output}"
        variables :input
      end

      result = template.format(input: "bird")
      expect(result).to include("Translate these examples:")
      expect(result).to include("cat -> chat")
      expect(result).to include("dog -> chien")
      expect(result).to include("Now: bird")
    end
  end

  describe "OpenRouter::Prompt factory methods" do
    it "creates simple template" do
      template = OpenRouter::Prompt.template(
        "Hello {name}",
        variables: [:name]
      )

      expect(template.format(name: "World")).to eq("Hello World")
    end

    it "creates few-shot template" do
      template = OpenRouter::Prompt.few_shot(
        prefix: "Examples:",
        suffix: "Input: {word}",
        examples: [{ word: "hello", translation: "hola" }],
        example_template: "{word} = {translation}",
        variables: [:word]
      )

      result = template.format(word: "goodbye")
      expect(result).to include("Examples:")
      expect(result).to include("hello = hola")
      expect(result).to include("Input: goodbye")
    end

    it "creates chat template using DSL" do
      template = OpenRouter::Prompt.chat do
        template "System: {system_prompt}\nUser: {user_message}"
        variables :system_prompt, :user_message
      end

      messages = template.to_messages(
        system_prompt: "You are helpful",
        user_message: "Hello"
      )

      expect(messages).to eq([
                               { role: "system", content: "You are helpful" },
                               { role: "user", content: "Hello" }
                             ])
    end
  end

  describe "edge cases" do
    it "handles templates with no variables" do
      template = described_class.new(
        template: "Hello World",
        input_variables: []
      )

      expect(template.format).to eq("Hello World")
    end

    it "requires either template or suffix" do
      expect do
        described_class.new(input_variables: [:test])
      end.to raise_error(ArgumentError, /Either template or suffix must be provided/)
    end

    it "requires example_template when examples provided" do
      expect do
        described_class.new(
          suffix: "Test",
          examples: [{ a: 1 }],
          input_variables: []
        )
      end.to raise_error(ArgumentError, /example_template is required/)
    end

    it "extracts variables from template automatically" do
      template = described_class.new(
        template: "Hello {name}, you are {age} years old"
      )

      # Should work without explicitly defining input_variables
      result = template.format(name: "Alice", age: 30)
      expect(result).to eq("Hello Alice, you are 30 years old")
    end
  end
end
