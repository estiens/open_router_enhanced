# frozen_string_literal: true

RSpec.describe OpenRouter::Schema do
  describe ".define" do
    it "creates schema with DSL" do
      schema = OpenRouter::Schema.define("weather", strict: true) do
        string :location, required: true, description: "City name"
        number :temperature, required: true, description: "Temperature in Celsius"
        string :conditions, required: true, description: "Weather conditions"
        no_additional_properties
      end

      expect(schema.name).to eq("weather")
      expect(schema.strict).to be true
      expect(schema.schema[:properties][:location][:type]).to eq("string")
      expect(schema.schema[:required]).to include("location", "temperature", "conditions")
      expect(schema.schema[:additionalProperties]).to be false
    end

    it "supports nested objects" do
      schema = OpenRouter::Schema.define("user") do
        string :name, required: true
        object :address, required: true do
          string :street, required: true
          string :city, required: true
          string :country, required: true
        end
      end

      address_props = schema.schema[:properties][:address][:properties]
      expect(address_props[:street][:type]).to eq("string")
      expect(address_props[:city][:type]).to eq("string")
      expect(schema.schema[:properties][:address][:required]).to include("street", "city", "country")
    end

    it "supports arrays with typed items" do
      schema = OpenRouter::Schema.define("book_list") do
        array :books, required: true do
          object do
            string :title, required: true
            string :author, required: true
            integer :pages
          end
        end
      end

      books_def = schema.schema[:properties][:books]
      expect(books_def[:type]).to eq("array")
      expect(books_def[:items][:type]).to eq("object")
      expect(books_def[:items][:properties][:title][:type]).to eq("string")
    end

    it "supports simple array items" do
      schema = OpenRouter::Schema.define("tags") do
        array :tags, required: true do
          string description: "A tag"
        end
      end

      tags_def = schema.schema[:properties][:tags]
      expect(tags_def[:items][:type]).to eq("string")
      expect(tags_def[:items][:description]).to eq("A tag")
    end
  end

  describe ".new" do
    it "creates schema from hash" do
      schema_def = {
        type: "object",
        properties: {
          name: { type: "string" }
        },
        required: [:name]
      }

      schema = OpenRouter::Schema.new("test", schema_def)
      expect(schema.name).to eq("test")
      expect(schema.schema[:properties][:name][:type]).to eq("string")
    end
  end

  describe "#to_h" do
    it "returns proper OpenRouter format" do
      schema = OpenRouter::Schema.define("weather") do
        string :location, required: true
        number :temperature, required: true
      end

      hash = schema.to_h
      expect(hash[:name]).to eq("weather")
      expect(hash[:strict]).to be true
      expect(hash[:schema][:type]).to eq("object")
      expect(hash[:schema][:properties]).to be_a(Hash)
      expect(hash[:schema][:required]).to be_an(Array)
    end

    it "respects declared optionality — optional fields are NOT forced into required" do
      schema = OpenRouter::Schema.define("user") do
        string :name, required: true
        string :nickname
        integer :age
      end

      hash = schema.to_h

      expect(hash[:schema][:required]).to eq(["name"])
      # optional fields keep their plain (non-nullable) type in the honest form
      expect(hash[:schema][:properties][:nickname][:type]).to eq("string")
    end

    it "keeps nested objects honest about their own optional fields" do
      schema = OpenRouter::Schema.define("user") do
        object :address, required: true do
          string :street, required: true
          string :zip
        end
      end

      address = schema.to_h[:schema][:properties][:address]
      expect(address[:required]).to eq(["street"])
    end
  end

  describe "#to_strict_h (native json_schema form)" do
    let(:schema) do
      OpenRouter::Schema.define("user") do
        string :name, required: true
        string :nickname
        object :address, required: true do
          string :street, required: true
          string :zip
        end
      end
    end

    it "lists every property in required so strict providers don't 400" do
      hash = schema.to_strict_h

      expect(hash[:schema][:required]).to contain_exactly("name", "nickname", "address")
      expect(hash[:schema][:properties][:address][:required]).to contain_exactly("street", "zip")
    end

    it "expresses optionality by making optional fields nullable, not mandatory-with-a-real-value" do
      hash = schema.to_strict_h

      expect(hash[:schema][:properties][:nickname][:type]).to eq(%w[string null])
      expect(hash[:schema][:properties][:address][:properties][:zip][:type]).to eq(%w[string null])
      # required fields stay strictly typed
      expect(hash[:schema][:properties][:name][:type]).to eq("string")
    end

    it "does not mutate the underlying schema" do
      schema.to_strict_h

      expect(schema.pure_schema[:required]).to contain_exactly("name", "address")
      expect(schema.pure_schema[:properties][:nickname][:type]).to eq("string")
      expect(schema.pure_schema[:properties][:address][:required]).to eq(["street"])
    end
  end

  describe "validation" do
    it "requires name" do
      expect do
        OpenRouter::Schema.new("", {})
      end.to raise_error(ArgumentError, /name/)
    end

    it "requires hash schema" do
      expect do
        OpenRouter::Schema.new("test", "not a hash")
      end.to raise_error(ArgumentError, /hash/)
    end
  end

  describe "property types" do
    it "supports all basic types" do
      schema = OpenRouter::Schema.define("types_test") do
        string :str_field
        integer :int_field
        number :num_field
        boolean :bool_field
        array :arr_field
        object :obj_field
      end

      props = schema.schema[:properties]
      expect(props[:str_field][:type]).to eq("string")
      expect(props[:int_field][:type]).to eq("integer")
      expect(props[:num_field][:type]).to eq("number")
      expect(props[:bool_field][:type]).to eq("boolean")
      expect(props[:arr_field][:type]).to eq("array")
      expect(props[:obj_field][:type]).to eq("object")
    end

    it "supports property options" do
      schema = OpenRouter::Schema.define("options_test") do
        string :name, required: true, description: "User name", minLength: 1, maxLength: 50
        integer :age, minimum: 0, maximum: 150
      end

      name_prop = schema.schema[:properties][:name]
      age_prop = schema.schema[:properties][:age]

      expect(name_prop[:description]).to eq("User name")
      expect(name_prop[:minLength]).to eq(1)
      expect(name_prop[:maxLength]).to eq(50)
      expect(age_prop[:minimum]).to eq(0)
      expect(age_prop[:maximum]).to eq(150)
      expect(schema.schema[:required]).to include("name")
    end
  end

  describe "strict mode" do
    it "defaults to strict true" do
      schema = OpenRouter::Schema.define("test") do
        string :name
      end

      expect(schema.strict).to be true
    end

    it "can be set to false" do
      schema = OpenRouter::Schema.define("test", strict: false) do
        string :name
      end

      expect(schema.strict).to be false
    end

    it "sets additionalProperties to false when strict" do
      schema = OpenRouter::Schema.define("test") do
        strict true
        string :name
      end

      expect(schema.schema[:additionalProperties]).to be false
    end

    it "sets additionalProperties to true when non-strict" do
      schema = OpenRouter::Schema.define("test") do
        strict false
        string :name
      end

      expect(schema.schema[:additionalProperties]).to be true
    end

    it "allows changing strict mode within DSL" do
      schema = OpenRouter::Schema.define("test") do
        strict false
        string :name
        additional_properties true
      end

      expect(schema.schema[:additionalProperties]).to be true
    end
  end

  # Only test validation if json-schema is available
  describe "validation", if: defined?(JSON::Validator) do
    let(:schema) do
      OpenRouter::Schema.define("person") do
        string :name, required: true
        integer :age, required: true, minimum: 0
      end
    end

    it "validates correct data" do
      data = { "name" => "John", "age" => 30 }
      expect(schema.validate(data)).to be true
      expect(schema.validation_errors(data)).to be_empty
    end

    it "rejects invalid data" do
      data = { "name" => "John", "age" => -5 }
      expect(schema.validate(data)).to be false
      expect(schema.validation_errors(data)).not_to be_empty
    end

    it "rejects missing required fields" do
      data = { "name" => "John" }
      expect(schema.validate(data)).to be false
      expect(schema.validation_errors(data)).not_to be_empty
    end
  end

  describe "validation availability" do
    let(:schema) { OpenRouter::Schema.new("test", {}) }

    it "detects when JSON::Validator is available" do
      if defined?(JSON::Validator)
        expect(schema.validation_available?).to be true
      else
        expect(schema.validation_available?).to be false
      end
    end
  end
end
