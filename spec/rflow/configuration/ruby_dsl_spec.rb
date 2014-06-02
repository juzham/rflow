require 'spec_helper'
require 'rflow/configuration'

class RFlow
  class Configuration
    describe RubyDSL do
      before(:each) do
        ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"
        Configuration.migrate_database
      end

      it "should correctly process an empty DSL" do
        described_class.configure {}

        Shard.should have(1).shard
        Component.should have(0).components
        Port.should have(0).ports
        Connection.should have(0).connections
      end

      it "should correctly process a component declaration" do
        described_class.configure do |c|
          c.component 'boom', 'town', 'opt1' => 'OPT1', 'opt2' => 'OPT2'
        end

        Shard.should have(1).shard
        Component.should have(1).component
        Port.should have(0).ports
        Connection.should have(0).connections

        Component.first.tap do |c|
          c.name.should == 'boom'
          c.specification.should == 'town'
          c.options.should == {'opt1' => 'OPT1', 'opt2' => 'OPT2'}
        end
      end

      it "should correctly process a connect declaration" do
        described_class.configure do |c|
          c.component 'first', 'First'
          c.component 'second', 'Second'
          c.connect 'first#out' => 'second#in'
          c.connect 'first#out' => 'second#in[inkey]'
          c.connect 'first#out[outkey]' => 'second#in'
          c.connect 'first#out[outkey]' => 'second#in[inkey]'
        end

        Shard.should have(1).shard
        Component.should have(2).components
        Port.should have(2).ports
        Connection.should have(4).connections

        first_component = Component.where(name: 'first').first.tap do |component|
          component.specification.should == 'First'
          component.should have(0).input_ports
          component.should have(1).output_port
          component.output_ports.first.name.should == 'out'

          component.output_ports.first.should have(4).connections
          component.output_ports.first.connections.tap do |connections|
            connections[0].input_port_key.should be_nil
            connections[0].output_port_key.should be_nil
            connections[1].input_port_key.should == 'inkey'
            connections[1].output_port_key.should be_nil
            connections[2].input_port_key.should be_nil
            connections[2].output_port_key.should == 'outkey'
            connections[3].input_port_key.should == 'inkey'
            connections[3].output_port_key.should == 'outkey'
          end
        end

        Component.where(name: 'second').first.tap do |component|
          component.specification.should == 'Second'
          component.should have(1).input_port
          component.input_ports.first.name.should == 'in'
          component.should have(0).output_ports

          component.input_ports.first.should have(4).connections
          component.input_ports.first.connections.should == first_component.output_ports.first.connections
        end
      end

      it "should correctly process shard declarations" do
        described_class.configure do |c|
          c.component 'first', 'First', :opt1 => 'opt1'

          c.shard "s1", :process => 2 do |s|
            s.component 'second', 'Second', :opt1 => 'opt1', "opt2" => "opt2"
          end

          c.shard "s2", :type => :process, :count => 10 do |s|
            s.component 'third', 'Third'
            s.component 'fourth', 'Fourth'
          end

          c.component 'fifth', 'Fifth'

          c.connect 'first#out' => 'second#in'
          c.connect 'second#out[outkey]' => 'third#in[inkey]'
          c.connect 'second#out' => 'third#in2'
          c.connect 'third#out' => 'fourth#in'
          c.connect 'third#out' => 'fifth#in'
        end

        Shard.should have(3).shards
        Component.should have(5).components
        Port.should have(8).ports
        Connection.should have(5).connections

        Shard.all.tap do |shards|
          shards.map(&:name).should == ['DEFAULT', 's1', 's2']
          shards.first.components.all.map(&:name).should == ['first', 'fifth']
          shards.second.components.all.map(&:name).should == ['second']
          shards.third.components.all.map(&:name).should == ['third', 'fourth']
        end

        Port.all.map(&:name).should == ['out', 'in', 'out', 'in', 'in2', 'out', 'in', 'in']

        Connection.all.map(&:name).should ==
          ['first#out=>second#in',
           'second#out[outkey]=>third#in[inkey]',
           'second#out=>third#in2',
           'third#out=>fourth#in',
           'third#out=>fifth#in']
      end

      it "should not allow two components with the same name" do
        expect {
          described_class.configure do |c|
            c.component 'first', 'First'
            c.component 'first', 'First'
          end
        }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "should not allow two shards with the same name" do
        expect {
          described_class.configure do |c|
            c.shard("s1", :process => 2) {}
            c.shard("s1", :process => 2) {}
          end
        }.to raise_error
      end
    end
  end
end