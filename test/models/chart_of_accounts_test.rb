require 'test_helper'

class ChartOfAccountsTest < Minitest::Unit::TestCase
  def setup
    @chart = ChartOfAccounts.new
  end

  def test_can_add_an_account
    @chart.add_account :checking, type: :asset, open_date: jan_1_2000
    assert_equal 1, @chart.size
  end

  def test_adding_account_can_default_open_date
    @chart.add_account :checking, type: :asset
    assert_equal 1, @chart.size
    assert_equal Projector::ABSOLUTE_START, @chart.fetch(:checking).open_date
  end

  def test_can_set_opening_balance
    @chart.add_account :checking, type: :asset, opening_balance: 500
    assert_equal [500], @chart.map(&:balance)
  end

  def test_balanced_iff_opening_balances_zero_out
    assert_equal 0, @chart.balance
    @chart.add_account :checking, type: :asset, opening_balance: 500
    assert_equal 500, @chart.balance
    @chart.add_account :slush, type: :equity, opening_balance: 500
    assert_equal 0, @chart.balance
  end

  def test_can_tag
    @chart.add_account :checking, type: :asset, tags: %i(foo)
    assert @chart.fetch(:checking).tag? :foo
  end

  def test_can_add_a_child_account
    @chart.add_account :my_bank, type: :asset
    @chart.split_account :my_bank, into: %i(checking)
  end

  def test_can_add_a_child_account_with_opening_balances
    @chart.add_account :my_bank, type: :asset, opening_balance: 200
    @chart.split_account :my_bank, into: { checking: { amount: 50 }, savings: { amount: 150 }}
    assert_equal 200, @chart.fetch(:my_bank).balance
    assert_equal 50, @chart.fetch(:checking).balance
    assert_equal 150, @chart.fetch(:savings).balance
    assert_equal 200, @chart.balance
  end

  def test_can_add_a_child_account_with_tags
    @chart.add_account :my_bank, type: :asset, tags: %i(foo)
    @chart.split_account :my_bank, into: [:checking, [:savings, { tags: %i(bar) }]]
    assert @chart.fetch(:checking).tag? :foo
    refute @chart.fetch(:checking).tag? :bar
    assert @chart.fetch(:savings).tag? :foo
    assert @chart.fetch(:savings).tag? :bar
  end

  def test_net_worth
    add_smattering_of_accounts
    # Net worth is assets minus liabilities
    assert_equal (25 + 400 + 15000) - (13000), @chart.net_worth
  end

  def test_applying_fixed_transaction
    @chart.add_account :checking, type: :asset
    @chart.add_account :job, type: :revenue

    fixed_transaction = Transaction.new(
      date: jan_1_2000,
      debits:  [{ amount: 1234, account_id: :checking, credit_or_debit: :debit },
                { amount: 12,   account_id: :job,      credit_or_debit: :debit }],
      credits: [{ amount: 1234, account_id: :job,      credit_or_debit: :credit},
                { amount: 12,   account_id: :checking, credit_or_debit: :credit}],
    )

    @chart.apply_transaction fixed_transaction
    assert_equal 1222, @chart.net_worth
  end

  def test_applying_transaction_with_percentages
    @chart.add_account :checking, type: :asset
    @chart.add_account :investment, type: :asset, opening_balance: 200000
    @chart.add_account :investment_revenue, type: :revenue

    percentage_transaction = Transaction.new(
      date: dec_31_2000,
      debit:  { percent: 0.06, of: :investment, account_id: :checking,           credit_or_debit: :debit },
      credit: { percent: 0.06, of: :investment, account_id: :investment_revenue, credit_or_debit: :credit },
    )

    @chart.apply_transaction percentage_transaction
    assert_equal 212000, @chart.net_worth
    assert_equal 12000, @chart.fetch(:checking).balance
  end

  def test_applying_transaction_for_non_existent_or_future_accounts_raises_error
    @chart.add_account :checking, type: :asset, open_date: jan_1_2000
    @chart.add_account :job, type: :revenue

    transaction = Transaction.new(
      date: jan_2_2000,
      debit:  { amount: 1234, account_id: :no_existe, credit_or_debit: :debit },
      credit: { amount: 1234, account_id: :job,       credit_or_debit: :credit },
    )

    assert_raises Projector::AccountDoesNotExist do
      @chart.apply_transaction transaction
    end
  end

  def test_serialize
    add_smattering_of_accounts
    expected_hash = {
      checking: { type: :asset,     opening_balance: 25    },
      savings:  { type: :asset,     opening_balance: 400   },
      auto:     { type: :asset,     opening_balance: 15000 },
      bills:    { type: :expense,   opening_balance: 26    },
      car_loan: { type: :liability, opening_balance: 13000 },
      new_job:  { type: :revenue,   opening_balance: 500   },
    }
    assert_equal expected_hash.keys, @chart.serialize.keys
    expected_hash.each do |key, expected_value|
      assert_equal expected_value, @chart.serialize.fetch(key)
    end
    assert_equal expected_hash, @chart.serialize
  end

  def test_account_balance_with_splits
    @chart.add_account :my_bank, type: :asset
    @chart.add_account :job, type: :revenue
    @chart.split_account :my_bank, into: %i(checking savings)
    @chart.split_account :checking, into: %i(checking_1 checking_2)

    @chart.apply_transaction Transaction.new(
      date: jan_1_2000,
      debit:  { amount: 1, account_id: :my_bank, credit_or_debit: :debit },
      credit: { amount: 1, account_id: :job, credit_or_debit: :credit },
    )
    @chart.apply_transaction Transaction.new(
      date: jan_1_2000,
      debit:  { amount: 5, account_id: :checking, credit_or_debit: :debit },
      credit: { amount: 5, account_id: :job, credit_or_debit: :credit },
    )
    @chart.apply_transaction Transaction.new(
      date: jan_1_2000,
      debit:  { amount: 12, account_id: :checking_1, credit_or_debit: :debit },
      credit: { amount: 12, account_id: :job, credit_or_debit: :credit },
    )

    assert_equal 12, @chart.account_balance(:checking_1)
    assert_equal 0,  @chart.account_balance(:checking_2)
    assert_equal 18, @chart.account_balance(:job)
    assert_equal 17, @chart.account_balance(:checking)
    assert_equal 0,  @chart.account_balance(:savings)
    assert_equal 18, @chart.account_balance(:my_bank)
  end

  private

  def add_smattering_of_accounts
    @chart.add_account :checking, type: :asset, opening_balance: 25
    @chart.add_account :savings, type: :asset, opening_balance: 400
    @chart.add_account :auto, type: :asset, opening_balance: 15000
    @chart.add_account :bills, type: :expense, opening_balance: 26
    @chart.add_account :car_loan, type: :liability, opening_balance: 13000
    @chart.add_account :new_job, type: :revenue, opening_balance: 500
  end
end
