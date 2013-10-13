require 'test_helper'

class AccountTest < Minitest::Unit::TestCase
  def setup
    @chart = ChartOfAccounts.new
    @account = @chart.add_account :foo, type: :asset
  end

  # Closed means "are the books closed?", e.g. are there any transactions that
  # haven't been processed
  def test_closed_returns_true_iff_no_transaction_entries
    assert @account.closed?
    add_transaction_entry
    refute @account.closed?
  end

  def test_close_freezes_and_returns_account_if_closed
    new_account = @account.close!

    assert @account.frozen?
    assert_equal new_account.object_id, @account.object_id
  end

  def test_close_freezes_and_returns_new_closed_account_if_unclosed
    add_transaction_entry
    new_account = @account.close!

    assert @account.frozen?
    refute_equal new_account.object_id, @account.object_id
  end

  private

  def add_transaction_entry
    entry = TransactionEntry.new_debit account_id: :foo, amount: 1
    entry.calculate @chart
    @account.add_entry entry
  end
end
