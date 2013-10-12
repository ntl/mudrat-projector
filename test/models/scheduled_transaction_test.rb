require 'test_helper'

class ScheduledTransactionTest < Minitest::Unit::TestCase
  def test_slice_does_not_return_leftover_if_ending_within_slice_date
    @schedule = Schedule.new every_month until: dec_31_2000
    leftover = @schedule.advance(jan_1_2000..dec_31_2000)
    assert_nil leftover
  end

  def test_slice_returns_leftover_if_schedule_has_no_end
    @schedule = Schedule.new every_month
    leftover = @schedule.advance(jan_1_2000..dec_31_2000)
    
    expected_schedule = { scalar: 1, unit: :month }
    assert_equal expected_schedule, leftover
  end

  def test_slice_returns_leftover_if_ending_after_slice_date
    @schedule = Schedule.new every_month until: jun_30_2001
    leftover = @schedule.advance(jan_1_2000..dec_31_2000)
    
    expected_schedule = { scalar: 1, unit: :month, count: 6 }
    assert_equal expected_schedule, leftover
  end

  def test_slice_prorates_final_period
    @schedule = Schedule.new every_month until: apr_15_2000

    expected_prorates = [1, 1, 1, 0.5]
    actual_prorates = []
    @schedule.advance(jan_1_2000..dec_31_2000) do |_, prorate|
      actual_prorates.push prorate
    end

    assert_equal expected_prorates, actual_prorates
  end

  def test_handles_start_after_projection
    @schedule = Schedule.new every_month(from: apr_1_2000, until: jun_15_2000)

    expected_prorates = [1, 1, 0.5]
    actual_prorates = []
    @schedule.advance(apr_1_2000..jun_15_2000) do |_, prorate|
      actual_prorates.push prorate
    end

    assert_equal expected_prorates, actual_prorates
  end

  def test_handles_start_during_range_and_end_after_range
    @schedule = Schedule.new every_month(from: apr_16_2000, until: jun_15_2001)

    expected_prorates = [1, 1, 1, 1, 1, 1, 1, 0.5 ]
    expected_leftover = { scalar: 1, unit: :month, count: 7.5 }

    actual_prorates = []
    actual_leftover = @schedule.advance(apr_1_2000..nov_30_2000) do |_, prorate|
      actual_prorates.push prorate
    end

    assert_equal expected_prorates, actual_prorates
    assert_equal expected_leftover, actual_leftover
  end
end
