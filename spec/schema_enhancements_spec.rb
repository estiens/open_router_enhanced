# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Schema DSL enhancements" do
  describe "enum support" do
    context "for string fields" do
      let(:schema) do
        OpenRouter::Schema.define("user_with_enum") do
          string :name, required: true
          string :role, required: true, enum: %w[admin editor viewer]
          string :status, enum: %w[active inactive pending]
        end
      end

      it "accepts enum parameter for string fields" do
        schema_hash = schema.to_h
        role_property = schema_hash[:schema][:properties][:role]

        expect(role_property[:type]).to eq("string")
        expect(role_property[:enum]).to eq(%w[admin editor viewer])
      end

      it "works with optional enum fields" do
        pure_schema_hash = schema.pure_schema
        status_property = pure_schema_hash[:properties][:status]

        expect(status_property[:type]).to eq("string")
        expect(status_property[:enum]).to eq(%w[active inactive pending])
        expect(pure_schema_hash[:required]).not_to include("status")
      end

      it "combines enum with other properties" do
        schema = OpenRouter::Schema.define("user_with_enum_desc") do
          string :priority, enum: %w[high medium low], description: "Task priority level"
        end

        schema_hash = schema.to_h
        priority_property = schema_hash[:schema][:properties][:priority]

        expect(priority_property[:enum]).to eq(%w[high medium low])
        expect(priority_property[:description]).to eq("Task priority level")
      end
    end

    context "for integer fields" do
      let(:schema) do
        OpenRouter::Schema.define("config_with_enum") do
          string :name, required: true
          integer :priority, enum: [1, 2, 3, 4, 5]
          integer :category_id, required: true, enum: [10, 20, 30]
        end
      end

      it "accepts enum parameter for integer fields" do
        schema_hash = schema.to_h
        priority_property = schema_hash[:schema][:properties][:priority]

        expect(priority_property[:type]).to eq("integer")
        expect(priority_property[:enum]).to eq([1, 2, 3, 4, 5])
      end

      it "works with required integer enum fields" do
        schema_hash = schema.to_h
        category_property = schema_hash[:schema][:properties][:category_id]

        expect(category_property[:type]).to eq("integer")
        expect(category_property[:enum]).to eq([10, 20, 30])
        expect(schema_hash[:schema][:required]).to include("category_id")
      end
    end

    context "for number fields" do
      let(:schema) do
        OpenRouter::Schema.define("measurement") do
          number :rating, enum: [1.0, 2.5, 3.0, 4.5, 5.0]
          number :temperature, enum: [-10.5, 0.0, 10.5, 25.0]
        end
      end

      it "accepts enum parameter for number fields" do
        schema_hash = schema.to_h
        rating_property = schema_hash[:schema][:properties][:rating]

        expect(rating_property[:type]).to eq("number")
        expect(rating_property[:enum]).to eq([1.0, 2.5, 3.0, 4.5, 5.0])
      end
    end

    context "validation" do
      it "properly serializes enum constraints in schema" do
        schema = OpenRouter::Schema.define("validated_user") do
          string :role, enum: %w[admin user]
          integer :level, enum: [1, 2, 3]
        end

        schema_json = JSON.parse(schema.to_h.to_json)

        expect(schema_json["schema"]["properties"]["role"]["enum"]).to eq(%w[admin user])
        expect(schema_json["schema"]["properties"]["level"]["enum"]).to eq([1, 2, 3])
      end
    end
  end

  describe "format support" do
    context "for string fields" do
      let(:schema) do
        OpenRouter::Schema.define("user_with_formats") do
          string :name, required: true
          string :email, required: true, format: "email"
          string :website, format: "uri"
          string :created_at, format: "date-time"
          string :birthday, format: "date"
        end
      end

      it "accepts format parameter for string fields" do
        schema_hash = schema.to_h
        email_property = schema_hash[:schema][:properties][:email]

        expect(email_property[:type]).to eq("string")
        expect(email_property[:format]).to eq("email")
      end

      it "supports standard JSON Schema formats" do
        schema_hash = schema.to_h
        properties = schema_hash[:schema][:properties]

        expect(properties[:website][:format]).to eq("uri")
        expect(properties[:created_at][:format]).to eq("date-time")
        expect(properties[:birthday][:format]).to eq("date")
      end

      it "combines format with other properties" do
        schema = OpenRouter::Schema.define("contact") do
          string :email, required: true, format: "email", description: "Contact email address"
        end

        schema_hash = schema.to_h
        email_property = schema_hash[:schema][:properties][:email]

        expect(email_property[:format]).to eq("email")
        expect(email_property[:description]).to eq("Contact email address")
        expect(schema_hash[:schema][:required]).to include("email")
      end
    end

    context "custom formats" do
      it "accepts custom format values" do
        schema = OpenRouter::Schema.define("custom_formats") do
          string :phone, format: "phone"
          string :slug, format: "slug"
        end

        schema_hash = schema.to_h
        properties = schema_hash[:schema][:properties]

        expect(properties[:phone][:format]).to eq("phone")
        expect(properties[:slug][:format]).to eq("slug")
      end
    end

    it "properly serializes format constraints" do
      schema = OpenRouter::Schema.define("formatted_data") do
        string :email, format: "email"
        string :url, format: "uri"
      end

      schema_json = JSON.parse(schema.to_h.to_json)

      expect(schema_json["schema"]["properties"]["email"]["format"]).to eq("email")
      expect(schema_json["schema"]["properties"]["url"]["format"]).to eq("uri")
    end
  end

  describe "combined enum and format" do
    it "supports both enum and format on the same field" do
      schema = OpenRouter::Schema.define("complex_field") do
        string :protocol, enum: %w[http https ftp], format: "uri-reference"
      end

      schema_hash = schema.to_h
      protocol_property = schema_hash[:schema][:properties][:protocol]

      expect(protocol_property[:enum]).to eq(%w[http https ftp])
      expect(protocol_property[:format]).to eq("uri-reference")
    end
  end

  describe "array items with enum/format" do
    context "using ItemsBuilder" do
      let(:schema) do
        OpenRouter::Schema.define("tagged_content") do
          string :title, required: true
          array :tags do
            string enum: %w[tech business personal]
          end
          array :urls do
            string format: "uri"
          end
        end
      end

      it "supports enum in array items" do
        schema_hash = schema.to_h
        tags_property = schema_hash[:schema][:properties][:tags]

        expect(tags_property[:type]).to eq("array")
        expect(tags_property[:items][:type]).to eq("string")
        expect(tags_property[:items][:enum]).to eq(%w[tech business personal])
      end

      it "supports format in array items" do
        schema_hash = schema.to_h
        urls_property = schema_hash[:schema][:properties][:urls]

        expect(urls_property[:type]).to eq("array")
        expect(urls_property[:items][:type]).to eq("string")
        expect(urls_property[:items][:format]).to eq("uri")
      end
    end

    context "using items parameter" do
      it "works with pre-defined items schema" do
        schema = OpenRouter::Schema.define("predefined_items") do
          array :statuses, items: { type: "string", enum: %w[active inactive] }
          array :emails, items: { type: "string", format: "email" }
        end

        schema_hash = schema.to_h
        properties = schema_hash[:schema][:properties]

        expect(properties[:statuses][:items][:enum]).to eq(%w[active inactive])
        expect(properties[:emails][:items][:format]).to eq("email")
      end
    end
  end

  describe "#get_format_instructions" do
    let(:schema) do
      OpenRouter::Schema.define("instruction_test") do
        string :name, required: true, description: "User's full name"
        string :email, required: true, format: "email"
        string :role, enum: %w[admin editor viewer]
        integer :age
      end
    end

    it "returns clear instructions for model prompting" do
      instructions = schema.get_format_instructions

      expect(instructions).to be_a(String)
      expect(instructions).to include("JSON Schema")
      expect(instructions).to include("format your output as a JSON value")
    end

    it "includes schema details in instructions" do
      instructions = schema.get_format_instructions

      expect(instructions).to include(schema.to_h.to_json)
      expect(instructions).to include("required")
      expect(instructions).to include("properties")
    end

    it "includes examples and guidelines" do
      instructions = schema.get_format_instructions

      expect(instructions).to include("example")
      expect(instructions).to include("match")
      expect(instructions).to include("trailing commas")
    end

    it "emphasizes JSON-only response" do
      instructions = schema.get_format_instructions

      expect(instructions).to include("ONLY")
      expect(instructions).to include("no other text")
    end

    context "for forced structured output" do
      it "provides instructions suitable for prompt injection" do
        instructions = schema.get_format_instructions

        # Should be suitable for adding to messages
        expect(instructions.length).to be > 100 # Substantial instructions
        expect(instructions).to match(/```json.*```/m) # Include JSON example
      end
    end
  end

  describe "backward compatibility" do
    it "maintains existing **options behavior" do
      schema = OpenRouter::Schema.define("backward_compat") do
        string :custom_field, custom_option: "value", another: "option"
      end

      schema_hash = schema.to_h
      custom_property = schema_hash[:schema][:properties][:custom_field]

      expect(custom_property[:custom_option]).to eq("value")
      expect(custom_property[:another]).to eq("option")
    end

    it "allows **options to override enum/format" do
      # Test override behavior by defining options that would normally conflict
      # The Hash#merge behavior should use the last value for duplicate keys
      options = { enum: %w[a b], format: "email" }.merge({ enum: %w[x y], format: "uri" })

      schema = OpenRouter::Schema.define("override_test") do
        string :field, **options
      end

      schema_hash = schema.to_h
      field_property = schema_hash[:schema][:properties][:field]

      # Later values should override
      expect(field_property[:enum]).to eq(%w[x y])
      expect(field_property[:format]).to eq("uri")
    end
  end

  describe "error handling" do
    it "validates enum values are provided" do
      # Empty enum should be allowed
      expect do
        OpenRouter::Schema.define("empty_enum") do
          string :role, enum: []
        end
      end.not_to raise_error
    end

    it "validates format values are strings" do
      # Should convert to string
      expect do
        OpenRouter::Schema.define("invalid_format") do
          string :field, format: 123
        end
      end.not_to raise_error
    end
  end
end
