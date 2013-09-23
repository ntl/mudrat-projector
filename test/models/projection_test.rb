require 'test_helper'

class ProjectionTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2000
  end

  def method_missing sym, *args, &block
    return super if block_given? || args.size > 0
    begin
      Date.parse sym.to_s
    rescue ArgumentError => ae
      super
    end
  end

  private

  def epoch
    jan_1_1970
  end

  def every_month _end = nil
    {
      end:    _end,
      number: 1,
      type:   :recurring,
      unit:   :month,
    }
  end

  def projection
    @projector.project to: dec_31_2000
  end
end

class ProjectorAccountsTest < ProjectionTest
  def test_add_account_defaults_name_to_id_when_hash_is_supplied
    @projector.add_account :checking, type: :asset
    assert_equal 'Checking', @projector.accounts[:checking].name
  end

  def test_add_account_refuses_to_overwrite_account
    @projector.add_account :checking, type: :asset
    assert_raises Projector::AccountExists do
      @projector.add_account :checking, type: :asset
    end
  end

  def test_add_account_refuses_to_add_account_without_valid_type
    assert_raises Projector::InvalidAccount do
      @projector.add_account :checking, type: nil
    end
    assert_raises Projector::InvalidAccount do
      @projector.add_account :checking, type: :foozle
    end
  end

  def test_add_accounts_defaults_open_date_to_epoch
    @projector.add_account :checking, type: :asset
    assert_equal epoch, @projector.accounts[:checking].open_date
  end

  def test_adding_a_sub_account
    parent = @projector.add_account(
      :checking,
      open_date: jan_8_2000,
      type:      :asset,
    )

    child, _ = @projector.split_account :checking, into: %i(checking_sub_1 checking_sub_2)

    assert_equal :checking,  child.parent_id
    assert_equal jan_8_2000, child.open_date
    assert_equal :asset,     child.type
  end

  def test_supplying_an_opening_balance
    @projector.add_account(
      :checking,
      open_date:       jan_1_2000,
      opening_balance: 500,
      type:            :asset,
    )
    refute @projector.balanced?

    assert_raises Projector::BalanceError do
      @projector.add_account(
        :savings,
        open_date:       jan_2_2000,
        opening_balance: 500,
        type:            :asset,
      )
    end

    @projector.add_account(
      :estate,
      open_date:       jan_1_2000,
      opening_balance: 500,
      type:            :equity,
    )
    assert @projector.balanced?
    assert_equal 500, projection.net_worth
  end

  def test_accounts_must_be_balanced_to_run_projection
    @projector.add_account(
      :checking,
      open_date:       jan_1_2000,
      opening_balance: 500,
      type:            :asset,
    )
    refute @projector.balanced?

    assert_raises Projector::BalanceError do
      @projector.project to: dec_31_2000
    end
  end

  def test_add_accounts_passes_account_hashes_to_add_account
    assert_equal 0, @projector.accounts.size
    @projector.accounts = { checking: { type: :asset } }
    assert_equal 1, @projector.accounts.size
  end
end

class ProjectorSingleTransactionTest < ProjectionTest
  def setup
    super
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_single_transaction_without_split
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    assert_equal 1000, projection.net_worth
    assert_equal 1000, projection.account_balance(:checking)
    assert_equal 1000, projection.account_balance(:nustartup_inc)
  end

  def test_far_future_transaction
    @projector.add_transaction(
      date: jan_1_2010,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    assert_equal 0, projection.net_worth
  end

  def test_single_transaction_to_sub_account_without_split
    @projector.split_account :checking, into: %i(checking_sub_1 checking_sub_2)

    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking_sub_1],
    )

    assert_equal 1000, projection.account_balance(:checking)
    assert_equal 1000, projection.account_balance(:checking_sub_1)
    assert_equal 0,    projection.account_balance(:checking_sub_2)
  end

  def test_single_transaction_with_split
    @projector.add_account :savings, type: :asset
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debits: [ [500, :checking], [500, :savings]],
    )

    assert_equal 1000, projection.net_worth
  end

  def test_recurring_transaction_surrounding_the_projection_range
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month,
    )
    assert_equal 48000, projection.net_worth
  end

  def test_recurring_transaction_starting_before_the_projection_range
    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: dec_31_1999,
        credit: [4000, :nustartup_inc],
        debit:  [4000, :checking],
        schedule: every_month,
      )
    end
  end

  def test_recurring_transaction_within_the_projection_range
    @projector.add_transaction(
      date: feb_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(may_31_2000),
    )
    assert_equal 16000, projection.net_worth
  end

  def test_recurring_transaction_after_the_projection_range
    @projector.add_transaction(
      date: feb_1_2001,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(may_31_2001),
    )
    assert_equal 0, projection.net_worth
  end

  def test_single_transaction_which_does_not_balance
    assert_raises Projector::BalanceError do
      @projector.add_transaction(
        date: jan_1_2000,
        credit: [1000, :nustartup_inc],
        debit:  [999, :checking],
      )
    end

    @projector.add_account :savings, type: :asset
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debits: [
        [999, :checking],
        [1, :savings],
      ],
    )
  end

  def test_add_transactions_passes_transactions_hashes_to_add_transaction
    assert_equal 0, @projector.transactions.size
    @projector.transactions = [{
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    }]
    assert_equal 1, @projector.transactions.size
  end
end

class ProjectorNetWorthTest < ProjectionTest
  def setup
    super
    @projector.accounts = {
      checking: { type: :asset, opening_balance: 1000 },
      nustartup_inc: { type: :revenue, opening_balance: 0 },
      credit_card: { type: :liability, opening_balance: 0 },
      estate: { type: :equity, opening_balance: 1000 },
    }
    @projector.transactions = [{
      date: jan_1_2000,
      credit: [2000, :nustartup_inc],
      debit:  [2000, :checking],
      schedule: every_month,
    },{
      date: jul_1_2000,
      credit: [5000, :credit_card],
      debit: [5000, :checking],
    }]
  end

  def test_initial_net_worth_is_initial_assets_minus_liabilities
    assert_equal 1000, projection.initial_net_worth
    assert_equal 1000 + 24000, projection.net_worth
    assert_equal 24000, projection.net_worth_delta
  end
end

class ProjectorSourcedFromProjectionTest < ProjectionTest
  def setup
    super
    @old_projector = @projector
    @old_projector.accounts = {
      checking: { type: :asset },
      nustartup_inc: { type: :revenue },
      big_company_inc: { type: :revenue, open_date: jul_1_2001 },
    }
    @old_projector.transactions = [{
      date: jan_1_2000,
      credit: [2000, :nustartup_inc],
      debit:  [2000, :checking],
    },{
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(jun_30_2001),
    },{
      date: jul_1_2001,
      credit: [5000, :big_company_inc],
      debit:  [5000, :checking],
      schedule: every_month,
    },{
      date: jul_1_2001,
      credit: [6500, :big_company_inc],
      debit:  [6500, :checking],
    }]
    @initial_projection = @old_projector.project to: dec_31_2000
    @projector = Projector.new @initial_projection
  end

  def test_projection_discards_finished_transactions_on_import
    assert_equal 4, @old_projector.transactions.size
    assert_equal 3, @projector.transactions.size
  end

  def test_from_is_set_to_end_of_projection
    assert_equal jan_1_2001, @projector.from
  end

  def test_accounts_are_setup_with_opening_balances_matching_prior_closing_balances
    assert_equal 50000, @projector.accounts[:checking].opening_balance
    assert_equal 50000, @projector.accounts[:nustartup_inc].opening_balance
    assert_equal 0,     @projector.accounts[:big_company_inc].opening_balance
  end

  def test_next_years_projection
    assert_equal 50000, @initial_projection.net_worth
    assert_equal 50000, projection.initial_net_worth
    assert_equal 50000 + (24000 + 30000 + 6500), projection.net_worth
  end

  private

  def projection
    @projector.project to: dec_31_2001
  end
end

class ProjectorCompoundInterestTest < ProjectionTest
  def setup
    skip
    @projector.accounts = {
      checking:      { type: :asset,     },
      loan:          { type: :liability, },
      loan_interest: { type: :expense,   },
    }

    @projector.transactions = [{
      date: jan_1_2000,
      credit: [{ amount: :payment,       account: :checking },
               { amount: :initial_value, account: :loan }],
      debits: [{ amount: :interest,      account: :loan_interest },
               { amount: :principal,     account: :loan },
               { amount: :initial_value, account: :checking }],
      schedule: {
        initial_value: 200000,
        interest:      5.000,
        term_length:   360,
        term_unit:     :month,
        type:          :compound,
      },
    }]
  end

  def test_interest_and_principal_paid_in_first_year
    interest  = 4984.90
    principal = 1456.96

    assert_equal interest, projection.account_balance(:loan_interest)
    assert_equal 0 - (interest + principal), projection.account_balance(:checking)
    assert_equal 200000 - principal, projection.account_balance(:loan)

    assert_equal 200000 - (interest + prinicpal) - (20000 - princpal),
      projection.net_worth
  end
end

class ProjectorJobAndAMortgageGauntletTest < ProjectionTest
  def setup
    super
    skip
    @projector.accounts = {
      checking:          { type: :asset,    opening_balance: 50000 },
      estate:            { type: :equity,   opening_balance: 50000 },
      nustartup_inc:     { type: :revenue,  tags: [:w2] },
      mortgage:          { type: :liability },
      my_home_expenses:  { type: :expense   },
      my_home:           { type: :asset,    tags: [:primary_residence] },
    }

    @projector.transactions = [{
      date: jan_1_2000,
      credit:  { amount: 4000, account: :nustartup_inc },
      debit:   { amount: 4000, account: :checking },
      schedule: {
        number: 1,
        unit:   :month,
        type:   :recurring,
      }
    },{
      date: jul_1_2000,
      credit:  { amount: 50000, account: :checking },
      debit:   { amount: 50000, account: :my_home },
    },{
      date: jul_1_2000,
      credit: [{ amount: :payment,       account: :checking },
               { amount: :initial_value, account: :mortgage }],
      debits: [{ amount: :interest,      account: :my_home_expenses },
               { amount: :principal,     account: :mortgage },
               { amount: :initial_value, account: :my_home }],
      schedule: {
        initial_value: 200000,
        interest:      5.000,
        term_length:   360,
        term_unit:     :month,
        type:          :compound_interest,
      },
    }]
  end

  def test_calculates_interest_as_expense_and_principal_as_asset
    expected_interest_paid  = 4984.90
    expected_principal_paid = 1456.96

    expected_checking_balance = 48000 - expected_interest_paid - expected_principal_paid

    assert_equal expected_checking_balance, projection.account_balance(:checking)
    assert_equal expected_principal_paid,   projection.account_balance(:checking)
    assert_equal (48000 - expected_interest_paid), projection.net_worth
  end
end
