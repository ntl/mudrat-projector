require 'test_helper'

class DateDiffTest < MiniTest::Unit::TestCase
  include DateDiff

  def setup
    @jan_1_2000  = Date.new 2000, 1, 1
    @jan_31_2000 = Date.new 2000, 1, 31
    @feb_1_2000  = Date.new 2000, 2, 1
    @jun_2_2000  = Date.new 2000, 6, 2
    @dec_30_2000 = Date.new 2000, 12, 30
    @dec_31_2000 = Date.new 2000, 12, 31
    @jan_2_2001  = Date.new 2001, 1, 2
  end

  def test_date_diff_method_invokes_appropriate_diff
    assert_equal (1.0 / 366.0), date_diff(:year, @jan_1_2000, @jan_1_2000)
    assert_equal (1.0 / 31.0), date_diff(:month, @jan_1_2000, @jan_1_2000)
    assert_equal (1.0 / 7.0), date_diff(:week, @jan_1_2000, @jan_1_2000)
    assert_equal 1.0, date_diff(:day, @jan_1_2000, @jan_1_2000)
  end

  def test_years_between_a_few_days
    assert_equal (1.0   / 366.0), diff_years(@jan_1_2000, @jan_1_2000)
    assert_equal (31.0  / 366.0), diff_years(@jan_1_2000, @jan_31_2000)
    assert_equal (32.0  / 366.0), diff_years(@jan_1_2000, @feb_1_2000)
    assert_equal (2/366.0 + 2/365.0), diff_years(@dec_30_2000, @jan_2_2001)
  end

  def test_quarters_between_a_few_days
    q1_2000 = (31 + 29 + 31).to_f
    q4_2000 = (31 + 30 + 31).to_f
    q1_2001 = (31 + 28 + 31).to_f
    assert_equal (1.0  / q1_2000), diff_quarters(@jan_1_2000, @jan_1_2000)
    assert_equal (31.0 / q1_2000), diff_quarters(@jan_1_2000, @jan_31_2000)
    assert_equal (32.0 / q1_2000), diff_quarters(@jan_1_2000, @feb_1_2000)
    assert_equal (2/q4_2000 + 2/q1_2001), diff_quarters(@dec_30_2000, @jan_2_2001)
  end

  def test_months_between_a_few_days
    assert_equal (1.0   / 31.0), diff_months(@jan_1_2000, @jan_1_2000)
    assert_equal (31.0  / 31.0), diff_months(@jan_1_2000, @jan_31_2000)
    assert_equal (1.0 + 1/29.0), diff_months(@jan_1_2000, @feb_1_2000)
    assert_equal (2.0/31.0 + 2.0/31.0), diff_months(@dec_30_2000, @jan_2_2001)
  end

  def test_weeks_between_a_few_days
    assert_equal (1.0   / 7.0), diff_weeks(@jan_1_2000, @jan_1_2000)
    assert_equal (31.0  / 7.0), diff_weeks(@jan_1_2000, @jan_31_2000)
    assert_equal (32.0  / 7.0), diff_weeks(@jan_1_2000, @feb_1_2000)
    assert_equal (2/7.0 + 2/7.0), diff_weeks(@dec_30_2000, @jan_2_2001)
  end

  def test_days_between_a_few_days
    assert_equal 1.0, diff_days(@jan_1_2000, @jan_1_2000)
    assert_equal 31.0, diff_days(@jan_1_2000, @jan_31_2000)
    assert_equal 32.0, diff_days(@jan_1_2000, @feb_1_2000)
    assert_equal 4.0, diff_days(@dec_30_2000, @jan_2_2001)
  end

  def test_six_months
    assert_equal ((1 + 29 + 31 + 30 + 31 + 2) / 366.0), diff_years(@jan_31_2000, @jun_2_2000)
    assert_equal (1.0/31.0 + 4.0 + 2.0/30.0), diff_months(@jan_31_2000, @jun_2_2000)
    assert_equal ((1 + 29 + 31 + 30 + 31 + 2) / 7.0), diff_weeks(@jan_31_2000, @jun_2_2000)
    assert_equal (1 + 29 + 31 + 30 + 31 + 2), diff_days(@jan_31_2000, @jun_2_2000)
  end

  def test_a_single_year
    assert_equal 1.0, diff_years(@jan_1_2000, @dec_31_2000)
    assert_equal 4.0, diff_quarters(@jan_1_2000, @dec_31_2000)
    assert_equal 12.0, diff_months(@jan_1_2000, @dec_31_2000)
  end

  def test_full_years
    dec_12_2004 = Date.new 2004, 12, 31
    assert_equal 5.0, diff_years(@jan_1_2000, dec_12_2004)
    assert_equal 20.0, diff_quarters(@jan_1_2000, dec_12_2004)
    assert_equal 60.0, diff_months(@jan_1_2000, dec_12_2004)
  end

  def test_a_year_and_four_days_across_a_leap_year
    assert_equal (2/366.0 + 1.0 + 2/365.0), diff_years(@dec_30_2000, Date.new(2002, 1, 2))
    assert_equal (2/31.0 + 12.0 + 2/31.0), diff_months(@dec_30_2000, Date.new(2002, 1, 2))
  end
end
