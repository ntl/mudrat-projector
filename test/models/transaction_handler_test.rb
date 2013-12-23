require 'test_helper'

class TransactionHandlerTest < Minitest::Test
  def setup
    @chart = ChartOfAccounts.new.tap do |c|
      c.add_account :checking, type: :asset
      c.add_account :job, type: :revenue
    end
    @projection = Projection.new range: (jan_1_2000..dec_31_2000), chart: @chart
    @transaction_handler = TransactionHandler.new projection: @projection
  end

  def test_routes_non_scheduled_transactions_in_range_to_projection
    @transaction_handler << fixed_transaction
    assert_equal 1, @projection.transaction_sequence.size
  end

  def test_does_not_route_non_scheduled_transactions_after_range_to_projection
    @transaction_handler << fixed_transaction(date: jan_1_2001)
    assert_equal 0, @projection.transaction_sequence.size
  end

  def test_routes_non_scheduled_transactions_after_range_to_next_projector
    @transaction_handler.next_projector = next_projector
    @transaction_handler << fixed_transaction(date: jan_1_2001)
    assert_equal 1, next_projector.transactions.size
  end

  def test_routes_a_scheduled_transaction_into_projector
    @transaction_handler << scheduled_transaction
    assert_equal 12, @projection.transaction_sequence.size
  end

  def test_routes_any_remainder_of_a_scheduled_transaction_into_next_projector
    @transaction_handler.next_projector = next_projector
    @transaction_handler << scheduled_transaction(end_date: july_1_2001)
    assert_equal 1, next_projector.transactions.size
  end

  def test_routes_future_transaction_into_next_projector
    @transaction_handler.next_projector = next_projector
    @transaction_handler << scheduled_transaction(start_date: jan_1_2040, end_date: jan_1_2041)
    assert_equal 0, @projection.transaction_sequence.size
    assert_equal 1, next_projector.transactions.size
  end

  private

  def fixed_transaction date: jan_1_2000, amount: 1000
    Transaction.new(
      date: date,
      debit:  { amount: amount, account_id: :checking },
      credit: { amount: amount, account_id: :job      },
    )
  end

  def scheduled_transaction start_date: jan_1_2000, end_date: dec_31_2000, amount: 1000
    ScheduledTransaction.new(
      date: start_date,
      debit:  { amount: amount, account_id: :checking },
      credit: { amount: amount, account_id: :job      },
      schedule: every_month(until: end_date),
    )
  end

  def next_projector
    @next_projector ||=
      Struct.new :transactions do
        def add_transaction transaction
          transactions.push transaction
        end
      end.new(Array.new)
  end
end
