require 'rflow/message'

class RFlow
  class Connection
    class << self
      def build(config)
        case config.type
        when 'RFlow::Configuration::ZMQConnection'
          RFlow::Connections::ZMQConnection.new(config)
        when 'RFlow::Configuration::BrokeredZMQConnection'
          RFlow::Connections::BrokeredZMQConnection.new(config)
        else
          raise ArgumentError, 'Only ZMQConnections currently supported'
        end
      end
    end

    attr_accessor :config, :uuid, :name, :options
    attr_writer :recv_callback
    protected
    attr_reader :recv_callback

    public
    def initialize(config)
      @config = config
      @uuid = config.uuid
      @name = config.name
      @options = config.options
    end

    # Subclass and implement to be able to handle future 'recv'
    # methods.  Will only be called in the context of a running
    # EventMachine reactor
    def connect_input!
      raise NotImplementedError, 'Raw connections do not support connect_input.  Please subclass and define a connect_input method.'
    end

    # Subclass and implement to be able to handle future 'send'
    # methods.  Will only be called in the context of a running
    # EventMachine reactor
    def connect_output!
      raise NotImplementedError, 'Raw connections do not support connect_output.  Please subclass and define a connect_output method.'
    end

    # Subclass and implement to handle outgoing messages.  The message
    # will be a RFlow::Message object and the subclasses are expected
    # to marshal it up into something that will be unmarshalled on the
    # other side
    def send_message(message)
      raise NotImplementedError, 'Raw connections do not support send_message.  Please subclass and define a send_message method.'
    end

    # Parent component will set this attribute if it expects to
    # recieve messages.  Connection subclass should call it
    # (recv_callback.call(message)) when it gets a new message, which
    # will be transmitted back to the parent component's
    # process_message method.  Sublcass is responsible for
    # deserializing whatever was on the wire into a RFlow::Message object
    def recv_callback
      @recv_callback ||= Proc.new {|message|}
    end

    def input_port_key; config.input_port_key; end
    def output_port_key; config.output_port_key; end
  end

  # Primarily for testing purposes. Captures whatever messages are sent on it.
  class MessageCollectingConnection < Connection
    attr_accessor :messages

    def initialize
      super(RFlow::Configuration::NullConnectionConfiguration.new)
      @messages = []
    end

    def send_message(message)
      @messages << message
    end
  end

  # Manually shuffle messages in-process from one output port to another output
  # port. Can be used to get a Facade pattern effect - to have one component
  # contain other components within it, shuttling messages in and out without
  # making the internal component visible to the larger RFlow network.
  class ForwardToOutputPort < Connection
    def initialize(target_port)
      super(RFlow::Configuration::NullConnectionConfiguration.new)
      @target_port = target_port
    end

    def send_message(message)
      @target_port.send_message(message)
    end
  end

  # Manually shuffle messages in-process from one output port to another output
  # port. Can be used to get a Facade pattern effect - to have one component
  # contain other components within it, shuttling messages in and out without
  # making the internal component visible to the larger RFlow network.
  class ForwardToInputPort < Connection
    def initialize(target_port)
      super(RFlow::Configuration::NullConnectionConfiguration.new)
      @receiver = target_port.component
      @target_port = target_port
    end

    def send_message(message)
      @receiver.process_message(@target_port, nil, self, message)
    end
  end
end
