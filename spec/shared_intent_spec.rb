require 'spec_helper'

describe SharedIntent do
  it 'has a version number' do
    expect(SharedIntent::VERSION).not_to be nil
  end

  class TestSharedIntents
    include SharedIntent
    register_route intents: "chime.testing", data_types: "chime.string"
  end

  let(:routable_response) do
    {
      "intents" => "chime.ActionIntent",
      "data_types" => "chime.string",
      "data" => "This is a response"
    }
  end
  subject { TestSharedIntents.new }

  describe "when included" do
    %i(run publish register_routes connection channel router_exchange queue logger).each do |method|
      it "responds to #{method}" do
        expect(subject.respond_to? method).to be true
      end
    end

    it "lets you register routes" do
      expect(TestSharedIntents.respond_to? :register_route).to be true
    end

    it "stored the appropriate routes on the class" do
      expected_routes = [
        { intents: "chime.testing", data_types: "chime.string" }
      ]
      expect(TestSharedIntents.routes).to match_array(expected_routes)
    end

    it "attempts to register the routes via the intent router" do
      dbl = double("router_exchange")
      expect(dbl).to receive(:publish).once.with(
        JSON.dump({"intents" => "chime.testing",
          "data_types" => "chime.string",
          "exchange" => "TestSharedIntentsExchange" }), routing_key: "add_route")
      allow(subject).to receive(:router_exchange).and_return dbl
      subject.register_routes
    end
  end

  describe "ensure_routing_maintained" do
    let(:message) { { "routing" => {} } }
    let(:response) { routable_response }

    context "no response provided" do
      let(:response) { nil }
      it "fails" do
        expect{subject.ensure_routing_maintained(message, response)}.
          to raise_exception("No response provided")
      end
    end

    context "no routing provided" do
      let(:message) { {} }
      it "fails" do
        expect{subject.ensure_routing_maintained(message, response)}.
          to raise_exception(KeyError, "key not found: \"routing\"")
      end
    end

    context "response is not a hash" do
      let(:response) { "blah blah" }
      it "fails" do
        expect{subject.ensure_routing_maintained(message, response)}.
         to raise_exception('Response must be a routable intent hash with: ["intents", "data_types", "data"]')
      end
    end

    context "response is not a routable hash" do
      let(:response) { { "data" => "not a routable hash" } }
      it "fails" do
        expect{subject.ensure_routing_maintained(message, response)}.
          to raise_exception('Response must be a routable intent hash. Missing: ["intents", "data_types"]')
      end
    end

    context "all data normal", :focus do
      it "merges the routing info to the response" do
        new_response = subject.ensure_routing_maintained(message, response)
        expect(new_response).to match(response.merge(message))
      end
    end
  end

  describe "_handle_message" do
    let(:delivery_info) { "delivery_info" }
    let(:metadata) { "metadata" }
    let(:hash_payload) { {"this" => "is the data", "routing" => {} } }
    let(:string_payload) { JSON.dump(hash_payload) }

    context "with a single return message" do
      it 'fails if handle_message is not defined' do
        expect{subject._handle_message(nil, nil, nil)}.to raise_exception("You must define handle_message")
      end

      it "parses the payload into a hash" do
        expect(subject).to receive(:handle_message).
                           with(delivery_info, metadata, hash_payload).
                           and_return(routable_response)
        response = subject._handle_message(delivery_info, metadata, string_payload)
        expect(response.length).to eq 1
      end
    end

    context "when multiple responses are returned" do
      it "parses each payload into a response" do
        expect(subject).to receive(:handle_message).
                           with(delivery_info, metadata, hash_payload).
                           and_return([routable_response,routable_response])
        response = subject._handle_message(delivery_info, metadata, string_payload)
        expect(response.length).to eq 2
      end
    end
  end
end
