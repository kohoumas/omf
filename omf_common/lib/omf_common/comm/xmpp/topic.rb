module OmfCommon
class Comm
class XMPP
  class Topic < OmfCommon::Comm::Topic
    %w(creation.ok creation.failed status released error warn).each do |itype|
      define_method("on_#{itype.gsub(/\./, '_')}") do |*args, &message_block|
        mid = args[0].mid if args[0]

        raise ArgumentError, 'Missing callback' if message_block.nil?

        event_block = proc do |event|
          message_block.call(OmfCommon::Message.parse(event.items.first.payload))
        end

        guard_block = proc do |event|
          (event.items?) && (!event.delayed?) &&
            event.items.first.payload &&
            (omf_message = OmfCommon::Message.parse(event.items.first.payload)) &&
            event.node == id.to_s &&
            omf_message.operation == :inform &&
            omf_message.read_content(:itype) == itype.upcase &&
            (mid ? (omf_message.cid == mid) : true)
        end

        OmfCommon.comm.topic_event(guard_block, &event_block)
      end
    end

    def on_message(message_guard_proc = nil, ref_id = 0, &message_block)
      @lock.synchronize do
        @on_message_cbks[ref_id] ||= []
        @on_message_cbks[ref_id] << message_block
      end

      event_block = proc do |event|
        @on_message_cbks.each do |id, cbks|
          cbks.each do |cbk|
            cbk.call(OmfCommon::Message.parse(event.items.first.payload))
          end
        end
      end

      guard_block = proc do |event|
        (event.items?) && (!event.delayed?) &&
          event.items.first.payload &&
          (omf_message = OmfCommon::Message.parse(event.items.first.payload)) &&
          event.node == id.to_s &&
          (valid_guard?(message_guard_proc) ? message_guard_proc.call(omf_message) : true)
      end
      OmfCommon.comm.topic_event(guard_block, &event_block)
    end

    def delete_on_message_cbk_by_id(id)
      @lock.synchronize do
        @on_message_cbks[id] && @on_message_cbks.reject! { |k| k == id.to_s }
      end
    end

    def inform(type, props = {}, core_props = {}, &block)
      msg = OmfCommon::Message.create(:inform, props, core_props.merge(itype: type))
      publish(msg, &block)
      self
    end

    def publish(msg, &block)
      _send_message(msg, &block)
    end

    def address
      "xmpp://#{id.to_s}@#{OmfCommon.comm.jid.domain}"
    end

    def on_subscribed(&block)
      return unless block

      @lock.synchronize do
        @on_subscrided_handlers << block
      end
    end

    private

    def initialize(id, opts = {}, &block)
      @on_message_cbks = Hashie::Mash.new

      id = $1 if id =~ /^xmpp:\/\/(.+)@.+$/

      super

      @on_subscrided_handlers = []

      topic_block = proc do |stanza|
        if stanza.error?
          block.call(stanza) if block
        else
          block.call(self) if block

          @lock.synchronize do
            @on_subscrided_handlers.each do |handler|
              handler.call
            end
          end
        end
      end

      OmfCommon.comm._create(id.to_s) do |stanza|
        if stanza.error?
          e_stanza = Blather::StanzaError.import(stanza)
          if e_stanza.name == :conflict
            # Topic exists, just subscribe to it.
            OmfCommon.comm._subscribe(id.to_s, &topic_block)
          else
            block.call(stanza) if block
          end
        else
          OmfCommon.comm._subscribe(id.to_s, &topic_block)
        end
      end
    end

    def _send_message(msg, &block)
      # while sending a message, need to setup handler for replying messages
      OmfCommon.comm.publish(self.id, msg) do |stanza|
        if !stanza.error? && !block.nil?
          on_error(msg, &block)
          on_warn(msg, &block)
          case msg.operation
          when :create
            on_creation_ok(msg, &block)
            on_creation_failed(msg, &block)
          when :configure, :request
            on_status(msg, &block)
          when :release
            on_released(msg, &block)
          end
        end
      end
    end

    def valid_guard?(guard_proc)
      guard_proc && guard_proc.class == Proc
    end

  end
end
end
end
