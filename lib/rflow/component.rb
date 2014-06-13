require 'ostruct'
require 'rflow/message'
require 'rflow/component/port'

class RFlow
  class Component
    class << self
      # Keep track of available component subclasses
      def inherited(subclass)
        RFlow::Configuration.add_available_component(subclass)
      end

      # Define an input port with a given name
      def input_port(name); define_port(defined_input_ports, name); end

      # Define an output port with a given name
      def output_port(name); define_port(defined_output_ports, name); end

      def defined_input_ports; @defined_input_ports ||= {}; end
      def defined_output_ports; @defined_output_ports ||= {}; end

      def define_port(collection, name)
        collection[name.to_s] = true

        # Create the port accessor method based on the port name
        define_method name.to_s.to_sym do
          port = ports.by_name[name.to_s]
          return port if port

          # If the port was not connected, return a port-like object
          # that can respond/log but doesn't send any data.  Note,
          # it won't be available in the 'by_uuid' collection, as it
          # doesn't have a configured uuid
          RFlow.logger.debug "'#{self.name}##{name}' not connected, creating a disconnected port"

          DisconnectedPort.new(name: name).tap {|p| ports << p }
        end
      end

      # Attempt to instantiate a component described by the config
      # specification. This assumes that the specification of a
      # component is a fully qualified Ruby class that has already
      # been loaded. It will first attempt to find subclasses of
      # RFlow::Component (in the available_components hash) and then
      # attempt to constantize the specification into a different
      # class. Future releases will support external (i.e. non-managed
      # components), but the current stuff only supports Ruby classes
      def build(config)
        raise NotImplementedError, "Non-managed components not yet implemented for component '#{config.name}' as '#{config.specification}' (#{config.uuid})" unless config.managed?

        RFlow.logger.debug "Instantiating component '#{config.name}' as '#{config.specification}' (#{config.uuid})"
        begin
          component_class = RFlow.configuration.available_components[config.specification]

          component = if component_class
                        RFlow.logger.debug "Component found in configuration.available_components['#{config.specification}']"
                        component_class.new
                      else
                        RFlow.logger.debug "Component not found in configuration.available_components, constantizing component '#{config.specification}'"
                        config.specification.constantize.new
                      end

          component.tap do |c|
            c.uuid = config.uuid
            c.name = config.name

            config.input_ports.each {|p| c.configure_input_port! p.name, uuid: p.uuid }
            config.output_ports.each {|p| c.configure_output_port! p.name, uuid: p.uuid }

            config.input_ports.each {|p| p.input_connections.each {|conn| c.configure_input_connection! p, conn } }
            config.output_ports.each {|p| p.output_connections.each {|conn| c.configure_output_connection! p, conn } }
          end
        rescue NameError => e
          raise RuntimeError, "Could not instantiate component '#{config.name}' as '#{config.specification}' (#{config.uuid}): the class '#{config.specification}' could not be loaded (#{e.message})"
        rescue Exception => e
          raise RuntimeError, "Could not instantiate component '#{config.name}' as '#{config.specification}' (#{config.uuid}): #{e.class} #{e.message}, because: #{e.backtrace.inspect}"
        end
      end
    end

    attr_accessor :uuid, :name
    attr_reader :ports

    def initialize
      @ports = PortCollection.new
    end

    # Returns a list of connected input ports.  Each port will have
    # one or more keys associated with a particular connection.
    def input_ports; ports.by_type["RFlow::Component::InputPort"]; end

    # Returns a list of connected output ports.  Each port will have
    # one or more keys associated with the particular connection.
    def output_ports; ports.by_type["RFlow::Component::OutputPort"]; end

    # Returns a list of disconnected output ports.
    def disconnected_ports; ports.by_type["RFlow::Component::DisconnectedPort"]; end

    def configure_input_port!(port_name, options = {})
      RFlow.logger.debug "Configuring component '#{name}' (#{uuid}) input port '#{port_name}' (#{options[:uuid]})"
      unless self.class.defined_input_ports.include? port_name
        raise ArgumentError, "Input port '#{port_name}' not defined on component '#{self.class}'"
      end
      ports << InputPort.new(name: port_name, uuid: options[:uuid])
    end

    def configure_output_port!(port_name, options = {})
      RFlow.logger.debug "Configuring component '#{name}' (#{uuid}) output port '#{port_name}' (#{options[:uuid]})"
      unless self.class.defined_output_ports.include? port_name
        raise ArgumentError, "Output port '#{port_name}' not defined on component '#{self.class}'"
      end
      ports << OutputPort.new(name: port_name, uuid: options[:uuid])
    end

    def configure_input_connection!(port, connection)
      RFlow.logger.debug "Attaching #{connection.type} connection '#{connection.name}' (#{connection.uuid}) to input port '#{port.name}' (#{port.uuid}), key '#{connection.input_port_key}'"
      ports.by_uuid[port.uuid].add_connection connection.input_port_key, Connection.build(connection)
    end

    def configure_output_connection!(port, connection)
      RFlow.logger.debug "Attaching #{connection.type} connection '#{connection.name}' (#{connection.uuid}) to output port '#{port.name}' (#{port.uuid}), key '#{connection.output_port_key}'"
      ports.by_uuid[port.uuid].add_connection connection.output_port_key, Connection.build(connection)
    end

    # Tell the component to establish its ports' connections, i.e. make
    # the connection.  Uses the underlying connection object.  Also
    # establishes the callbacks for each of the input ports
    def connect_inputs!
      input_ports.each {|port| port.recv_callback = method(:process_message) }
      input_ports.each(&:connect!)
    end

    # Tell the component to establish its ports' connections, i.e. make
    # the connection. Uses the underlying connection object.
    def connect_outputs!
      output_ports.each(&:connect!)
    end

    def to_s
      string = "Component '#{name}' (#{uuid})\n"
      ports.each do |port|
        port.keys.each do |key|
          port[key].each do |connection|
            string << "\t#{port.class.to_s} '#{port.name}' (#{port.uuid}) key '#{key}' connection '#{connection.name}' (#{connection.uuid})\n"
          end
        end
      end
      string
    end

    # Method that should be overridden by a subclass to provide for
    # component-specific configuration.  The subclass should use the
    # self.configuration attribute (@configuration) to store its
    # particular configuration.  The incoming deserialized_configuration
    # parameter is from the RFlow configuration database and is (most
    # likely) a hash.  Don't assume that the keys are symbols
    def configure!(deserialized_configuration); end

    # Main component running method.  Subclasses should implement if
    # they want to set up any EventMachine stuffs (servers, clients,
    # etc)
    def run!; end

    # Method called when a message is received on an input port.
    # Subclasses should implement if they want to receive messages
    def process_message(input_port, input_port_key, connection, message); end

    # Method called when RFlow is shutting down.  Subclasses should
    # implment to terminate any servers/clients (or let them finish)
    # and stop sending new data through the flow
    def shutdown!; end

    # Method called after all components have been shutdown! and just
    # before the global RFlow exit.  Sublcasses should implement to
    # cleanup any leftover state, e.g. flush file handles, etc
    def cleanup!; end
  end
end
