require 'spec_helper'

class RFlow
  class Component
    describe Port do
      it "should not be connected" do
        expect(described_class.new).not_to be_connected
      end
    end

    describe HashPort do
      it "should not be connected" do
        expect(described_class.new).not_to be_connected
      end
    end

    describe InputPort do
      context "#connect!" do
        it "should be connected" do
          connection = double('connection')
          expect(connection).to receive(:connect_input!)

          described_class.new.tap do |port|
            port.add_connection(nil, connection)
            expect(port).not_to be_connected
            port.connect!
            expect(port).to be_connected
          end
        end
      end
    end

    describe OutputPort do
      context "#connect!" do
        it "should be connected" do
          connection = double('connection')
          expect(connection).to receive(:connect_output!)

          described_class.new.tap do |port|
            port.add_connection(nil, connection)
            expect(port).not_to be_connected
            port.connect!
            expect(port).to be_connected
          end
        end
      end
    end
  end
end
