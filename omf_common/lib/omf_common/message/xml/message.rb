require 'niceogiri'
require 'hashie'
require 'securerandom'
require 'openssl'
require 'cgi'

require 'omf_common/message/xml/relaxng_schema'

module OmfCommon
class Message
class XML

  # @example To create a valid omf message, e.g. a 'create' message:
  #
  #   Message.create(:create,
  #                  { p1: 'p1_value', p2: { unit: 'u', precision: 2 } },
  #                  { guard: { p1: 'p1_value' } })
  class Message < OmfCommon::Message
    include Comparable

    OMF_NAMESPACE = "http://schema.mytestbed.net/omf/#{OmfCommon::PROTOCOL_VERSION}/protocol"

    attr_accessor :xml
    attr_accessor :content

    class << self
      # Create a OMF message
      def create(operation_type, properties = {}, core_elements= {})
        # For request messages, properties will be an array
        if properties.kind_of? Array
          properties = Hashie::Mash.new.tap do |mash|
            properties.each { |p| mash[p] = nil }
          end
        end

        properties = Hashie::Mash.new(properties)
        core_elements = Hashie::Mash.new(core_elements)

        if operation_type.to_sym == :create
          core_elements[:rtype] ||= properties[:type]
        end

        content = core_elements.merge({
          operation: operation_type,
          type: operation_type,
          properties: properties,
          src: 'bob'
        })

        new(content)
      end

      def parse(xml)
        raise ArgumentError, 'Can not parse an empty XML into OMF message' if xml.nil? || xml.empty?

        xml_node = Nokogiri::XML(xml).root

        self.create(xml_node.name.to_sym).tap do |message|
          message.xml = xml_node

          message.send(:_set_core, :mid, message.xml.attr('mid'))

          message.xml.elements.each do |el|
            unless %w(digest props guard).include? el.name
              message.send(:_set_core, el.name, message.read_content(el.name))
            end

            if el.name == 'props'
              message.read_element('props').first.element_children.each do |prop_node|
                message.send(:_set_property,
                             prop_node.element_name,
                             message.reconstruct_data(prop_node))
              end
            end

            if el.name == 'guard'
              message.read_element('guard').first.element_children.each do |guard_node|
                message.guard ||= Hashie::Mash.new
                message.guard[guard_node.element_name] = message.reconstruct_data(guard_node)
              end
            end
          end

          if OmfCommon::Measure.enabled? && !@@mid_list.include?(message.mid)
            MPMessage.inject(Time.now.to_f, message.operation.to_s, message.mid, message.cid, message.to_s.gsub("\n",''))
          end
        end
      end
    end

    def resource
      r_id = _get_property(:res_id)
      OmfCommon::Comm::XMPP::Topic.create(r_id)
    end

    def itype
      @content.itype.to_s.upcase.gsub(/_/, '.') unless @content.itype.nil?
    end

    def marshall
      build_xml
      @xml.to_xml
    end

    alias_method :to_xml, :marshall
    alias_method :to_s, :marshall

    def build_xml
      @xml = Niceogiri::XML::Node.new(self.operation.to_s, nil, OMF_NAMESPACE)

      @xml.write_attr(:mid, mid)
      @xml.add_child(Niceogiri::XML::Node.new(:props))
      @xml.add_child(Niceogiri::XML::Node.new(:guard)) if _get_core(:guard)

      (OMF_CORE_READ - [:mid, :guard, :operation]).each do |attr|
        attr_value = self.send(attr)

        next unless attr_value

        add_element(attr, attr_value) unless (self.operation != :release && attr == :res_id)
      end

      self.properties.each { |k, v| add_property(k, v) }
      self.guard.each { |k, v| add_property(k, v, :guard) } if _get_core(:guard)

      #digest = OpenSSL::Digest::SHA512.new(@xml.canonicalize)

      #add_element(:digest, digest)
      @xml
    end

    # Construct a property xml node
    #
    def add_property(key, value = nil, add_to = :props)
      key_node = Niceogiri::XML::Node.new(key)

      unless value.nil?
        key_node.write_attr('type', ruby_type_2_prop_type(value.class))
        c_node = value_node_set(value)

        if c_node.class == Array
          c_node.each { |c_n| key_node.add_child(c_n) }
        else
          key_node.add_child(c_node)
        end
      end
      read_element(add_to).first.add_child(key_node)
      key_node
    end

    def value_node_set(value, key = nil)
      case value
      when Hash
        [].tap do |array|
          value.each_pair do |k, v|
            n = Niceogiri::XML::Node.new(k)
            n.write_attr('type', ruby_type_2_prop_type(v.class))

            c_node = value_node_set(v, k)
            if c_node.class == Array
              c_node.each { |c_n| n.add_child(c_n) }
            else
              n.add_child(c_node)
            end
            array << n
          end
        end
      when Array
        value.map do |v|
          n = Niceogiri::XML::Node.new('item')
          n.write_attr('type', ruby_type_2_prop_type(v.class))

          c_node = value_node_set(v, 'item')
          if c_node.class == Array
            c_node.each { |c_n| n.add_child(c_n) }
          else
            n.add_child(c_node)
          end
          n
        end
      else
        if key.nil?
          string_value(value)
        else
          n = Niceogiri::XML::Node.new(key)
          n.add_child(string_value(value))
        end
      end
    end

    # Generate SHA1 of canonicalised xml and write into the ID attribute of the message
    #
    def sign
      write_attr('mid', SecureRandom.uuid)
      write_attr('ts', Time.now.utc.to_i)
      canonical_msg = self.canonicalize

      #priv_key =  OmfCommon::Key.instance.private_key
      #digest = OpenSSL::Digest::SHA512.new(canonical_msg)

      #signature = Base64.encode64(priv_key.sign(digest, canonical_msg)).encode('utf-8') if priv_key
      #write_attr('digest', digest)
      #write_attr('signature', signature) if signature

      if OmfCommon::Measure.enabled?
        MPMessage.inject(Time.now.to_f, operation.to_s, mid, cid, self.to_s.gsub("\n",''))
        @@mid_list << mid
      end
      self
    end

    # Validate against relaxng schema
    #
    def valid?
      build_xml

      validation = RelaxNGSchema.instance.validate(@xml.document)
      if validation.empty?
        true
      else
        logger.error validation.map(&:message).join("\n")
        logger.debug @xml.to_s
        false
      end
    end

    # Short cut for adding xml node
    #
    def add_element(key, value = nil, &block)
      key_node = Niceogiri::XML::Node.new(key)
      @xml.add_child(key_node)
      if block
        block.call(key_node)
      else
        key_node.content = value if value
      end
      key_node
    end

    # Short cut for grabbing a group of nodes using xpath, but with default namespace
    def element_by_xpath_with_default_namespace(xpath_without_ns)
      xpath_without_ns = xpath_without_ns.to_s
      @xml.xpath(xpath_without_ns.gsub(/(^|\/{1,2})(\w+)/, '\1xmlns:\2'), :xmlns => OMF_NAMESPACE)
    end

    # In case you think method :element_by_xpath_with_default_namespace is too long
    #
    alias_method :read_element, :element_by_xpath_with_default_namespace

    # We just want to know the content of an non-repeatable element
    #
    def read_content(element_name)
      element_content = read_element("#{element_name}").first.content rescue nil
      unless element_content.nil?
        element_content.empty? ? nil : element_content
      else
        nil
      end
    end

    # Reconstruct xml node into Ruby object
    #
    # @param [Niceogiri::XML::Node] property xml node
    # @return [Object] the content of the property, as string, integer, float, or mash(hash with indifferent access)
    def reconstruct_data(node, data_binding = nil)
      node_type =  node.attr('type')
      case node_type
      when 'array'
        node.element_children.map do |child|
          reconstruct_data(child, data_binding)
        end
      when /hash/
        mash ||= Hashie::Mash.new
        node.element_children.each do |child|
          mash[child.attr('key') || child.element_name] ||= reconstruct_data(child, data_binding)
        end
        mash
      when /boolean/
        node.content == "true"
      else
        if node.content.empty?
          nil
        elsif data_binding && node_type == 'string'
          ERB.new(node.content).result(data_binding)
        else
          node.content.ducktype
        end
      end
    end

    def <=>(another)
      @content <=> another.content
    end

    def properties
      @content.properties
    end

    def has_properties?
      @content.properties.empty?
    end

    def guard?
      @content.guard.empty?
    end

    # Pretty print for application event message
    #
    def print_app_event
      "APP_EVENT (#{read_property(:app)}, ##{read_property(:seq)}, #{read_property(:event)}): #{read_property(:msg)}"
    end

    # Iterate each property key value pair
    #
    def each_property(&block)
      properties.each { |k, v| block.call(k, v) }
    end


    def each_unbound_request_property(&block)
      raise "Can only be used for request messages. Got #{type}." if type != :request
      properties.each { |k, v| block.call(k, v) if v.nil? }
    end

    def each_bound_request_property(&block)
      raise "Can only be used for request messages. Got #{type}." if type != :request
      properties.each { |k, v| block.call(k, v) unless v.nil? }
    end

    def [](name, evaluate = false)
      value = properties[name]

      if evaluate && value.kind_of?(String)
        ERB.new(value).result(evaluate)
      else
        value
      end
    end

    alias_method :read_property, :[]

    alias_method :write_property, :[]=

    private

    def initialize(content = {})
      @content = content
      @content.mid = SecureRandom.uuid
      @content.ts = Time.now.utc.to_i
    end

    def _set_core(key, value)
      @content[key] = value
    end

    def _get_core(key)
      @content[key]
    end

    def _set_property(key, value)
      @content.properties[key] = value
    end

    def _get_property(key)
      @content.properties[key]
    end

    def ruby_type_2_prop_type(ruby_class_type)
      v_type = ruby_class_type.to_s.downcase
      case v_type
      when *%w(trueclass falseclass)
        'boolean'
      when *%w(fixnum bignum)
        'integer'
      else
        v_type
      end
    end

    # Get string of a value object, escape if object is string
    def string_value(value)
      if value.kind_of? String
        value = CGI::escape_html(value)
      else
        value = value.to_s
      end
      value
    end
  end
end
end
end

