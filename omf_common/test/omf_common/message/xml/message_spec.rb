require 'test_helper'
require 'omf_common/message/xml/message'

include OmfCommon

describe OmfCommon::Message::XML::Message do
  describe "when create message initialised" do
    before do
      # We will test prop value other than just strings
      @message = Message::XML::Message.create(:create,
                                     { p1: 'p1_value', p2: { unit: 'u', precision: 2 } },
                                     { rtype: 'bob', guard: { p1: 'p1_value' } })
    end

    it "must to be validated using relaxng schema" do
      @message.valid?.must_equal true
    end

    it "must be able to be serialised as XML" do
      @message.to_xml.must_match /^<create(.+)create>$/m
      @message.to_xml.must_match /<rtype>bob<\/rtype>/m
      @message.to_xml.must_match /<props(.+)props>/m
      @message.to_xml.must_match /<guard(.+)guard>/m
    end
  end

  describe "when release message initialised" do
    before do
      # We will test prop value other than just strings
      @message = Message::XML::Message.create(:release, {}, { res_id: 'bob', guard: { p1: 'p1_value' } })
    end

    it "must to be validated using relaxng schema" do
      @message.valid?.must_equal true
    end

    it "must be able to be serialised as XML" do
      @message.to_xml.must_match /^<release(.+)release>$/m
      @message.to_xml.must_match /<res_id>bob<\/res_id>/m
      @message.to_xml.must_match /<guard(.+)guard>/m
    end
  end

  describe "when asked to parse a XML element into Message::XML::Message object" do
    before do
      @xml = Message::XML::Message.create(
        :create,
        { type: 'vm',
          os: 'debian',
          memory: { value: 1024, unit: 'mb', precision: 0 },
          devices: [{ name: 'w0', driver: 'mod_bob'}, { name: 'w1', driver: ['mod1', 'mod2']} ],
          true: true,
          false: false,
          empty: nil,
          boolean_array: [false, true] },
        { guard: { os_type: 'linux' } }).to_xml
      @message = Message::XML::Message.parse(@xml)
    end

    it "must create the object correctly" do
      @message.must_be_kind_of Message::XML::Message
      @message.operation.must_equal :create
    end

    it "must provide normal xml xpath query" do
      @message.read_element("props").first.element_children.size.must_equal 8
      @message.read_content("props/memory/unit").must_equal 'mb'
    end

    it "must provide unified message property access" do
      @message["type"].must_equal 'vm'
      @message[:type].must_equal 'vm'
    end

    it "must provide guard information" do
      @message.guard[:os_type].must_equal 'linux'
    end

    it "must be able reconstruct complicate data" do
      # Each property iterator
      @message.each_property do |k, v|
        %w(type os memory devices true false empty boolean_array).must_include k
      end

      memory = @message[:memory]
      memory.must_be_kind_of Hashie::Mash
      memory.value.must_equal 1024
      memory.unit.must_equal 'mb'
      memory.precision.must_equal 0

      devices = @message[:devices]
      devices.must_be_kind_of Array
      devices.size.must_equal 2
      devices.find { |v| v.name == 'w1'}.driver.size.must_equal 2
    end

    it "must be able ducktype string xml content for numbers, boolean, empty string" do
      @message[:true].must_equal true
      @message[:false].must_equal false
      @message[:boolean_array].must_equal [false, true]
      @message[:empty].must_equal nil
    end

    it "must fail if parse an empty xml" do
      lambda { Message::XML::Message.parse("") }.must_raise ArgumentError
      lambda { Message::XML::Message.parse(nil) }.must_raise ArgumentError
    end
  end

  describe "when creating request messages" do
    it "must accept an array of properties instead of hash" do
      request_m = Message::XML::Message.create(:request, [:p1, :p2])
      request_m.valid?.must_equal true
      request_m[:p1].must_be_nil
    end
  end

  describe "when parsing inform message" do
    it "must validate against inform message schema" do
      msg = Message::XML::Message.parse <<-XML
        <inform xmlns="http://schema.mytestbed.net/omf/6.0/protocol" mid="bob">
          <src>xmpp://bob@localhost</src>
          <ts>100</ts>
          <itype>CREATION.OK</itype>
        </inform>
      XML

      msg.ts.must_equal "100"
      msg.itype.must_equal "CREATION.OK"

      msg.valid?.must_equal true
    end
  end
end
