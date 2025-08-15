# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::Tool do
  describe "DSL arrays of objects support" do
    it "supports array { items { object { ... }}} syntax" do
      tool = OpenRouter::Tool.define do
        name "process_users"
        description "Process a list of users"

        parameters do
          array :users, required: true, description: "Array of user objects" do
            items do
              object do
                string :name, required: true
                string :email, required: true
                number :age
              end
            end
          end
        end
      end

      tool_hash = tool.to_h
      users_param = tool_hash[:function][:parameters][:properties][:users]

      expect(users_param[:type]).to eq("array")
      expect(users_param[:items][:type]).to eq("object")
      expect(users_param[:items][:properties]).to have_key(:name)
      expect(users_param[:items][:properties]).to have_key(:email)
      expect(users_param[:items][:properties]).to have_key(:age)
      expect(users_param[:items][:required]).to contain_exactly(:name, :email)
    end

    it "supports nested object arrays" do
      tool = OpenRouter::Tool.define do
        name "process_companies"
        description "Process companies with their employees"

        parameters do
          array :companies, required: true do
            items do
              object do
                string :company_name, required: true
                array :employees do
                  items do
                    object do
                      string :name, required: true
                      string :role
                    end
                  end
                end
              end
            end
          end
        end
      end

      tool_hash = tool.to_h
      companies_param = tool_hash[:function][:parameters][:properties][:companies]

      # Check company level
      expect(companies_param[:items][:type]).to eq("object")
      expect(companies_param[:items][:properties]).to have_key(:company_name)
      expect(companies_param[:items][:properties]).to have_key(:employees)

      # Check nested employees array
      employees_param = companies_param[:items][:properties][:employees]
      expect(employees_param[:type]).to eq("array")
      expect(employees_param[:items][:type]).to eq("object")
      expect(employees_param[:items][:properties]).to have_key(:name)
      expect(employees_param[:items][:properties]).to have_key(:role)
      expect(employees_param[:items][:required]).to contain_exactly(:name)
    end

    it "falls back to hash syntax when object method is not available" do
      # This test shows that until object method is implemented,
      # users can still use hash syntax
      tool = OpenRouter::Tool.define do
        name "fallback_example"
        description "Example using hash syntax for arrays"
        parameters do
          array :items do
            items({
                    type: "object",
                    properties: {
                      name: { type: "string" },
                      count: { type: "number" }
                    },
                    required: ["name"],
                    additionalProperties: false
                  })
          end
        end
      end

      tool_hash = tool.to_h
      items_param = tool_hash[:function][:parameters][:properties][:items]

      expect(items_param[:items][:type]).to eq("object")
      expect(items_param[:items][:properties]).to have_key(:name)
      expect(items_param[:items][:properties]).to have_key(:count)
      expect(items_param[:items][:required]).to contain_exactly("name")
    end
  end
end
