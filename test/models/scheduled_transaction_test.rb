require 'test_helper'

class ScheduledTransactionTest < Minitest::Unit::TestCase
  def setup
    @chart = ChartOfAccounts.new
    @chart.add_account :checking, type: :asset
    @chart.add_account :job,      type: :revenue
  end

  def test_prorating
    in_range, _ = scheduled_transaction.slice apr_15_2000
    assert_equal [1000, 1000, 1000, 500], in_range.map { |t| t.credits.first.scalar }

    in_range, _ = scheduled_transaction_with_percentage.slice apr_15_2000
    assert_equal [0.25, 0.25, 0.25, 0.125], in_range.map { |t| t.credits.first.scalar }
  end

  def test_leftover
    _, leftover = scheduled_transaction(apr_15_2000).slice apr_15_2000
    assert_nil leftover

    _, leftover = scheduled_transaction(apr_16_2000).slice apr_15_2000
    refute_nil leftover

    assert_equal apr_16_2000, leftover.date
  end

  private

  def scheduled_transaction end_date = nil
    ScheduledTransaction.new(
      date: jan_1_2000,
      debit:  { account_id: :checking, amount: 1000 },
      credit: { account_id: :job,      amount: 1000 },
      schedule: every_month(until: end_date),
    )
  end

  def scheduled_transaction_with_percentage
    ScheduledTransaction.new(
      date: jan_1_2000,
      debit:  { account_id: :checking, percent: 0.25, of: :job },
      credit: { account_id: :job,      percent: 0.25, of: :job },
      schedule: every_month,
    )
  end
end
