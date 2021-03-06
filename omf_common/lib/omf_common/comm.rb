require 'omf_common/comm/topic'

module OmfCommon
  # PubSub communication class, can be extended with different implementations
  class Comm

    @@providers = {
      xmpp: {
        require: 'omf_common/comm/xmpp/communicator',
        constructor: 'OmfCommon::Comm::XMPP::Communicator',
        message_provider: {
          type: :xml
        }
      },
      amqp: {
        require: 'omf_common/comm/amqp/amqp_communicator',
        constructor: 'OmfCommon::Comm::AMQP::Communicator',
        message_provider: {
          type: :json
        }
      },
      local: {
        require: 'omf_common/comm/local/local_communicator',
        constructor: 'OmfCommon::Comm::Local::Communicator',
        message_provider: {
          type: :json
        }
      }
    }
    @@instance = nil

    #
    # opts:
    #   :type - pre installed comms provider
    #   :provider - custom provider (opts)
    #     :require - gem to load first (opts)
    #     :constructor - Class implementing provider
    #
    def self.init(opts)
      if @@instance
        raise "Comms layer already initialised"
      end
      unless provider = opts[:provider]
        unless type = opts[:type]
          if url = opts[:url]
            type = url.split(':')[0].to_sym
          end
        end
        provider = @@providers[type]
      end
      unless provider
        raise "Missing Comm provider declaration. Either define 'type', 'provider', or 'url'"
      end

      require provider[:require] if provider[:require]

      if class_name = provider[:constructor]
        provider_class = class_name.split('::').inject(Object) {|c,n| c.const_get(n) }
        inst = provider_class.new(opts)
      else
        raise "Missing communicator creation info - :constructor"
      end
      @@instance = inst
      Message.init(provider[:message_provider])
      inst.init(opts)
    end

    def self.instance
      @@instance
    end

    # Initialize comms layer
    #
    def init(opts = {})
      raise "Not implemented"
    end

    # Shut down comms layer
    def disconnect(opts = {})
      raise "Not implemented"
    end

    def on_connected(&block)
      raise "Not implemented"
    end

    # Create a new pubsub topic with additional configuration
    #
    # @param [String] topic Pubsub topic name
    def create_topic(topic, opts = {})
      raise "Not implemented"
    end

    # Delete a pubsub topic
    #
    # @param [String] topic Pubsub topic name
    def delete_topic(topic, &block)
      raise "Not implemented"
    end

    # Subscribe to a pubsub topic
    #
    # @param [String, Array] topic_name Pubsub topic name
    # @param [Hash] opts
    # @option opts [Boolean] :create_if_non_existent create the topic if non-existent, use this option with caution
    #
    def subscribe(topic_name, opts = {}, &block)
      tna = (topic_name.is_a? Array) ? topic_name : [topic_name]
      ta = tna.collect do |tn|
        t = create_topic(tn)
        if block
          block.call(t)
        end
        t
      end
      ta[0]
    end

    # Return the options used to initiate this
    # communicator.
    #
    def options()
      @opts
    end

    private
    def initialize(opts = {})
      @opts = opts
    end

  end
end
