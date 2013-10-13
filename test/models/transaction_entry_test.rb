require 'test_helper'

class TransactionEntryTest < MiniTest::Unit::TestCase
  def test_must_supply_type_of_debit_or_credit
    assert_raises ArgumentError do
      TransactionEntry.new credit_or_debit: :foo, amount: 1, account_id: :checking
    end
  end

  def test_must_supply_a_nonzero_amount
    assert_raises ArgumentError do
      TransactionEntry.new credit_or_debit: :credit, amount: 0, account_id: :checking
    end
  end

  def test_must_supply_an_account
    assert_raises KeyError do
      TransactionEntry.new credit_or_debit: :credit, amount: 1
    end
  end

  def test_calculate_amount_sets_amount_and_delta
    chart = ChartOfAccounts.new
    chart.add_account :checking, type: :asset, opening_balance: 1000
    chart.add_account :job, type: :revenue, opening_balance: 1000
    
    t1 = TransactionEntry.new credit_or_debit: :credit, amount: 1, account_id: :checking
    t1.calculate chart
    assert_equal 1, t1.amount
    assert_equal -1, t1.delta

    t2 = TransactionEntry.new credit_or_debit: :debit, percent: 0.5, of: :checking, account_id: :checking
    t2.calculate chart
    assert_equal 500, t2.amount
    assert_equal 500, t2.delta
  end
end
