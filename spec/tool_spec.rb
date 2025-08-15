# frozen_string_literal: true

RSpec.describe OpenRouter::Tool do
  describe ".define" do
    it "creates a tool with DSL" do
      tool = OpenRouter::Tool.define do
        name "search_books"
        description "Search for books"

        parameters do
          string :query, required: true, description: "Search query"
          integer :limit, description: "Max results"
        end
      end

      expect(tool.name).to eq("search_books")
      expect(tool.description).to eq("Search for books")
      expect(tool.parameters[:properties][:query][:type]).to eq("string")
      expect(tool.parameters[:required]).to include(:query)
    end

    it "supports array parameters with items" do
      tool = OpenRouter::Tool.define do
        name "process_list"
        description "Process a list"

        parameters do
          array :items, required: true do
            string description: "Item in the list"
          end
        end
      end

      expect(tool.parameters[:properties][:items][:type]).to eq("array")
      expect(tool.parameters[:properties][:items][:items][:type]).to eq("string")
    end

    it "supports nested object parameters" do
      tool = OpenRouter::Tool.define do
        name "create_user"
        description "Create a user"

        parameters do
          object :user, required: true do
            string :name, required: true
            integer :age
            boolean :active, required: true
          end
        end
      end

      user_props = tool.parameters[:properties][:user][:properties]
      expect(user_props[:name][:type]).to eq("string")
      expect(user_props[:age][:type]).to eq("integer")
      expect(user_props[:active][:type]).to eq("boolean")
      expect(tool.parameters[:properties][:user][:required]).to include(:name, :active)
    end
  end

  describe ".new" do
    it "creates a tool from hash definition" do
      definition = {
        name: "test_tool",
        description: "A test tool",
        parameters: {
          type: "object",
          properties: {
            input: { type: "string" }
          }
        }
      }

      tool = OpenRouter::Tool.new(definition)
      expect(tool.name).to eq("test_tool")
      expect(tool.description).to eq("A test tool")
    end

    it "accepts function format" do
      definition = {
        type: "function",
        function: {
          name: "test_tool",
          description: "A test tool",
          parameters: {
            type: "object",
            properties: {
              input: { type: "string" }
            }
          }
        }
      }

      tool = OpenRouter::Tool.new(definition)
      expect(tool.name).to eq("test_tool")
      expect(tool.type).to eq("function")
    end
  end

  describe "#to_h" do
    it "returns proper OpenRouter format" do
      tool = OpenRouter::Tool.define do
        name "search"
        description "Search function"
        parameters do
          string :query, required: true
        end
      end

      hash = tool.to_h
      expect(hash[:type]).to eq("function")
      expect(hash[:function][:name]).to eq("search")
      expect(hash[:function][:description]).to eq("Search function")
      expect(hash[:function][:parameters]).to be_a(Hash)
    end
  end

  describe "validation" do
    it "requires name" do
      expect do
        OpenRouter::Tool.new({ description: "No name" })
      end.to raise_error(ArgumentError, /name/)
    end

    it "requires description" do
      expect do
        OpenRouter::Tool.new({ name: "no_description" })
      end.to raise_error(ArgumentError, /description/)
    end

    it "validates parameters type" do
      expect do
        OpenRouter::Tool.new({
                               name: "test",
                               description: "test",
                               parameters: { type: "string" }
                             })
      end.to raise_error(ArgumentError, /object/)
    end
  end
end
