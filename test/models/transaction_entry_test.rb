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
end
