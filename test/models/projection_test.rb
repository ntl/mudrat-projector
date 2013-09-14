require 'test_helper'

class ProjectorTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new
    @projector.accounts = [{
      id:   :checking,
      name: 'Checking',
      type: :asset,
    }]
  end

  def test_simple_projection
    assert_equal 0, projection.net_worth

    @projector.transactions.push(
      amount:  50000.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      recurring_schedule: [1, :year],
    )

    assert_equal 500000, projection.net_worth
    assert_equal 1000000, projection(Date.new(2019, 12, 31)).net_worth

    @projector.transactions.push(
      amount:  -100.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      recurring_schedule: [1, :month],
    )
    assert_equal 488000, projection.net_worth
  end

  def test_projection_with_transaction_starting_and_ending_within_timeframe
    @projector.transactions.push(
      amount:   50000.0,
      date:     Date.new(2001, 1, 1),
      end_date: Date.new(2008, 12, 31),
      account:  :checking,
      recurring_schedule: [1, :year],
    )

    assert_equal 400000, projection.net_worth
  end

  private

  def projection date = Date.new(2009, 12, 31)
    @projector.project!(
      from: Date.new(2000, 1, 1),
      to: date,
    )
  end
end
