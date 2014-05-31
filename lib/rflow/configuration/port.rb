require 'active_record'
require 'rflow/configuration/uuid_keyed'

class RFlow
  class Configuration
    class Port < ConfigDB
      include UUIDKeyed
      include ActiveModel::Validations

      belongs_to :component,  :primary_key => 'uuid', :foreign_key => 'component_uuid'

      # TODO: Make some sort of component/port validation work here
      #validate :component_has_defined_port
    end

    # STI-based classes
    class InputPort < Port
      has_many :input_connections, :class_name => 'RFlow::Configuration::Connection', :primary_key => 'uuid', :foreign_key => 'input_port_uuid'
      has_many :connections, :class_name => 'RFlow::Configuration::Connection', :primary_key => 'uuid', :foreign_key => 'input_port_uuid'
    end

    class OutputPort < Port
      has_many :output_connections, :class_name => 'RFlow::Configuration::Connection', :primary_key => 'uuid', :foreign_key => 'output_port_uuid'
      has_many :connections, :class_name => 'RFlow::Configuration::Connection', :primary_key => 'uuid', :foreign_key => 'output_port_uuid'
    end
  end
end
