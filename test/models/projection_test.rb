require 'test_helper'

class ProjectionTest < Minitest::Test
  def setup
    @chart = ChartOfAccounts.new.tap do |c|
      c.add_account :checking, type: :asset
      c.add_account :job, type: :revenue
    end
    @projection = Projection.new range: (jan_1_2000..dec_31_2000), chart: @chart
  end

  def test_adding_transaction
    @projection << valid_transaction
    assert_equal 1, @projection.transaction_sequence.size
  end

  def test_adding_transactions_out_of_order
    @projection << (first  = valid_transaction(date: jan_3_2000))
    @projection << (second = valid_transaction(date: jan_2_2000))
    @projection << (third  = valid_transaction(date: jan_2_2000))
    @projection << (fourth = valid_transaction(date: jan_1_2000))

    assert_equal [fourth, second, third, first].map(&:date),
      @projection.transaction_sequence.map(&:date)
  end

  def test_project_freezes_projection_and_plays_transactions_through_chart
    add_valid_transactions
    assert_equal 0, @chart.net_worth

    @projection.project!
    assert @projection.frozen?

    assert_equal 3032, @chart.net_worth
  end

  def test_project_will_yield_to_block
    add_valid_transactions

    dates = []
    @projection.project! { |t| dates << t.date }

    assert_equal [jan_1_2000, feb_2_2000, mar_3_2000, apr_4_2000], dates
  end

  private

  def add_valid_transactions
    @projection << valid_transaction(date: jan_1_2000)
    @projection << valid_transaction(date: feb_2_2000, amount: 32)
    @projection << valid_transaction(date: mar_3_2000)
    @projection << valid_transaction(date: apr_4_2000)
  end

  def valid_transaction date: jan_1_2000, amount: 1000
    Transaction.new(
      date: date,
      debit:  { amount: amount, account_id: :checking },
      credit: { amount: amount, account_id: :job      },
    )
  end
end
