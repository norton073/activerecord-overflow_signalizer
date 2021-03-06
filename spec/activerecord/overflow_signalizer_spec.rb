require 'spec_helper'

RSpec.describe ActiveRecord::OverflowSignalizer do
  it 'has a version number' do
    expect(ActiveRecord::OverflowSignalizer::VERSION).not_to be nil
  end

  let(:max_int) do
    described_class::MAX_VALUE[TestIntModel.columns.select { |c| c.name == TestIntModel.primary_key }.first.sql_type]
  end

  let(:day) { 24 * 60 * 60 }

  describe '#analyse!' do
    context 'raise exception' do
      let(:logger) { Logger.new('/dev/null') }
      subject { described_class.new(logger: logger, models: [TestIntModel], days_count: 10) }

      context 'empty table' do
        it { expect { subject.analyse! }.not_to raise_error }
      end

      context 'unsupported type of primary key' do
        let(:today) { Time.now }
        before do
          (1..7).each do |t|
            record = TestStringModel.new(created_at: today - day * t, updated_at: today - day * t)
            record.id = "id#{t}"
            record.save!
          end
        end

        subject { described_class.new(models: [TestStringModel], days_count: 10, logger: logger) }

        it { expect { subject.analyse! }.not_to raise_error }
      end

      context 'not empty table' do
        let(:today) { Time.now }

        context 'overflow far' do
          before do
            (1..7).each do |t|
              TestIntModel.create!(created_at: today - day * t, updated_at: today - day * t)
            end
          end

          after do
            TestIntModel.connection.execute(%Q{ALTER SEQUENCE "int_test_id_seq" RESTART WITH 1;})
            TestIntModel.destroy_all
          end

          it { expect { subject.analyse! }.not_to raise_error }
        end

        context 'overflow soon' do
          before do
            TestIntModel.connection.execute(%Q{ALTER SEQUENCE "int_test_id_seq" RESTART WITH #{max_int - 16};})
            (1..7).each do |t|
              TestIntModel.create!(created_at: today - day * t, updated_at: today - day * t)
            end
          end

          after do
            TestIntModel.connection.execute(%Q{ALTER SEQUENCE "int_test_id_seq" RESTART WITH 1;})
            TestIntModel.destroy_all
          end

          it { expect { subject.analyse! }.to raise_error(described_class::Overflow) }
        end

        context 'overflowed' do
          before do
            TestIntModel.connection.execute(%Q{ALTER SEQUENCE "int_test_id_seq" RESTART WITH #{max_int - 6};})
            (1..7).each do |t|
              TestIntModel.create!(created_at: today - day * t, updated_at: today - day * t)
            end
          end

          after do
            TestIntModel.connection.execute(%Q{ALTER SEQUENCE "int_test_id_seq" RESTART WITH 1;})
            TestIntModel.destroy_all
          end

          it { expect { subject.analyse! }.to raise_error(described_class::Overflow) }
        end
      end
    end
  end
end
