# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Dependencies" do
  describe "Response requiring ActiveSupport" do
    it "uses with_indifferent_access which requires ActiveSupport" do
      # This test demonstrates the bug: Response uses with_indifferent_access
      # but doesn't require ActiveSupport in the file itself

      # Test that Response calls with_indifferent_access
      hash = { "test" => "data" }
      expect(hash).to receive(:with_indifferent_access).and_return(hash)

      OpenRouter::Response.new(hash)
    end

    it "fails if we try to instantiate a raw hash without ActiveSupport loaded" do
      # This would fail in an environment without ActiveSupport
      # We can simulate by stubbing the method to raise an error
      hash = { "test" => "data" }
      allow(hash).to receive(:with_indifferent_access).and_raise(NoMethodError,
                                                                 "undefined method `with_indifferent_access'")

      expect do
        OpenRouter::Response.new(hash)
      end.to raise_error(NoMethodError, /with_indifferent_access/)
    end
  end

  describe "Client requiring Set" do
    it "uses Set.new which requires the set library" do
      # This test demonstrates that Client uses Set but doesn't require it

      # Stub Set to track if it's being used
      expect(Set).to receive(:new).and_call_original

      OpenRouter::Client.new
    end

    it "fails if Set is not available" do
      # Simulate Set not being available
      stub_const("Set", nil)

      expect do
        OpenRouter::Client.new
      end.to raise_error(NoMethodError, /undefined method.*new.*nil/)
    end
  end

  describe "HTTP requiring JSON" do
    it "uses JSON.parse which requires the json library" do
      # This test demonstrates that HTTP module uses JSON but doesn't require it

      # Create a mock client that includes the HTTP module
      client = OpenRouter::Client.new

      # Test that JSON.parse is called in to_json_stream
      expect(JSON).to receive(:parse).and_call_original

      # Create a streaming proc that triggers JSON.parse
      stream_proc = client.send(:to_json_stream, user_proc: proc { |data| })

      # Simulate streaming data that contains JSON
      stream_proc.call("data: {\"test\": \"value\"}", nil)
    end

    it "fails if JSON is not available in to_json_stream" do
      client = OpenRouter::Client.new

      # Simulate JSON not being available
      stub_const("JSON", nil)

      expect do
        stream_proc = client.send(:to_json_stream, user_proc: proc { |data| })
        stream_proc.call("data: {\"test\": \"value\"}", nil)
      end.to raise_error(TypeError, /nil is not a class/)
    end
  end
end
