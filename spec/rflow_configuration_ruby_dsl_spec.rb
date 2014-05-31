require 'spec_helper.rb'
require 'rflow/configuration'

describe RFlow::Configuration::RubyDSL do
  before(:each) do
    ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"
    RFlow::Configuration.migrate_database
  end

  it "should correctly process an empty DSL" do
    described_class.configure { |c| }

    config = RFlow::Configuration.new
    RFlow::Configuration::Shard.count.should == 1
    RFlow::Configuration::Component.count.should == 0
    RFlow::Configuration::Port.count.should == 0
    RFlow::Configuration::Connection.count.should == 0
  end

  it "should correctly process a component declaration" do
    described_class.configure do |c|
      c.component 'boom', 'town', 'opt1' => 'OPT1', 'opt2' => 'OPT2'
    end

    config = RFlow::Configuration.new
    RFlow::Configuration::Shard.count.should == 1
    RFlow::Configuration::Component.count.should == 1
    RFlow::Configuration::Port.count.should == 0
    RFlow::Configuration::Connection.count.should == 0

    component = RFlow::Configuration::Component.all.first
    component.name.should == 'boom'
    component.specification.should == 'town'
    component.options.should == {'opt1' => 'OPT1', 'opt2' => 'OPT2'}
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

    config = RFlow::Configuration.new
    RFlow::Configuration::Shard.count.should == 1
    RFlow::Configuration::Component.count.should == 2
    RFlow::Configuration::Port.count.should == 2
    RFlow::Configuration::Connection.count.should == 4

    first_component = RFlow::Configuration::Component.where(name: 'first').first
    second_component = RFlow::Configuration::Component.where(name: 'second').first

    first_component.specification.should == 'First'
    first_component.input_ports.count.should == 0
    first_component.output_ports.count.should == 1
    first_component.output_ports.first.name.should == 'out'
    first_connections = first_component.output_ports.first.connections.all
    first_connections.count.should == 4
    first_connections[0].input_port_key.should be_nil
    first_connections[0].output_port_key.should be_nil
    first_connections[1].input_port_key.should == 'inkey'
    first_connections[1].output_port_key.should be_nil
    first_connections[2].input_port_key.should be_nil
    first_connections[2].output_port_key.should == 'outkey'
    first_connections[3].input_port_key.should == 'inkey'
    first_connections[3].output_port_key.should == 'outkey'

    second_component.specification.should == 'Second'
    second_component.input_ports.count.should == 1
    second_component.output_ports.count.should == 0
    second_component.input_ports.first.name.should == 'in'
    second_connections = second_component.input_ports.first.connections.all
    second_connections.count.should == 4

    first_connections.should == second_connections
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

    config = RFlow::Configuration.new
    RFlow::Configuration::Shard.count.should == 3
    RFlow::Configuration::Component.count.should == 5
    RFlow::Configuration::Port.count.should == 8
    RFlow::Configuration::Connection.count.should == 5

    shards = RFlow::Configuration::Shard.all
    shards.map(&:name).should == ['DEFAULT', 's1', 's2']
    shards.first.components.all.map(&:name).should == ['first', 'fifth']
    shards.second.components.all.map(&:name).should == ['second']
    shards.third.components.all.map(&:name).should == ['third', 'fourth']

    RFlow::Configuration::Port.all.map(&:name).should == ['out', 'in', 'out', 'in', 'in2', 'out', 'in', 'in']

    RFlow::Configuration::Connection.all.map(&:name).should ==
      ['first#out=>second#in',
       'second#out[outkey]=>third#in[inkey]',
       'second#out=>third#in2',
       'third#out=>fourth#in',
       'third#out=>fifth#in']
  end

  it "should not allow two components with the same name" do
    expect do
      described_class.configure do |c|
        c.component 'first', 'First'
        c.component 'first', 'First'
      end
    end.to raise_error
  end

  it "should not allow two shards with the same name" do
    expect do
      described_class.configure do |c|
        c.shard("s1", :process => 2) { |s| }
        c.shard("s1", :process => 2) { |s| }
      end
    end.to raise_error
  end
end
