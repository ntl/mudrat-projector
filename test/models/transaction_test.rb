require 'test_helper'

class TransactionTest < Minitest::Unit::TestCase
  def test_balanced_on_fixed_transactions
    assert Transaction.new(
      date: jan_1_2000,
      credits: [{ amount: 1, account_id: :checking }], 
      debits: [{ amount: 1, account_id: :bills }],
    ).balanced?

    refute Transaction.new(
      date: jan_1_2000,
      credits: [{ amount: 1, account_id: :checking }], 
      debits: [{ amount: 2, account_id: :bills }],
    ).balanced?
  end

  def test_balanced_on_percentage_transactions
    refute Transaction.new(
      date: jan_1_2000,
      credit: { percent: 25.0, of: :savings, account_id: :checking },
      debit: { amount: 25, account_id: :bills },
    ).balanced?

    refute Transaction.new(
      date: jan_1_2000,
      credit: { percent: 25.0, of: :savings, account_id: :checking }, 
      debit: { percent: 24.0, of: :savings, account_id: :bills },
    ).balanced?

    assert Transaction.new(
      date: jan_1_2000,
      credit: { percent: 25.0, of: :savings , account_id: :checking }, 
      debits: [{percent: 12.5, of: :savings , account_id: :bills },
               {percent: 12.5, of: :savings , account_id: :bills }],
    ).balanced?
  end

  def test_can_supply_a_single_credit_or_debit
    Transaction.new(
      date: jan_1_2000,
      credit: { amount: 1, account_id: :checking }, 
      debit: { amount: 1, account_id: :bills },
    )
    # Can't supply both a :credit and :credits
    assert_raises ArgumentError do
      Transaction.new(
        date: jan_1_2000,
        credit: { amount: 1, account_id: :checking }, 
        credits: [{ amount: 2, account_id: :checking }], 
        debits: [{ amount: 1, account_id: :bills }],
      )
    end
  end

  private

  def valid_transaction schedule: nil
    Transaction.new(
      date: jan_1_2000, 
      credits: [{ amount: 1, account_id: :checking }],
      debits:  [{ amount: 1, account_id: :bills }],
      schedule: schedule,
    )
  end
end
