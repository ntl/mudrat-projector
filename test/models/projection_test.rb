require 'test_helper'

class ProjectionTest < Minitest::Unit::TestCase
  def setup
    @chart = ChartOfAccounts.new.tap do |c|
      c.add_account :checking, type: :asset
      c.add_account :job, type: :revenue
    end
    @projection = Projection.new range: (jan_1_2000..dec_31_2000), chart: @chart
  end

  def test_cannot_add_transaction_outside_of_range
    assert_raises Projector::InvalidTransaction do
      @projection << valid_transaction(date: dec_31_1999)
    end
    assert_raises Projector::InvalidTransaction do
      @projection << valid_transaction(date: jan_1_2001)
    end
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

__END__

class ProjectionTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2000
  end

  private

  def run_projection date, &block
    @projector.project to: date, &block
  end

  def net_worth projection
    projection.account_balances(:asset) - projection.account_balances(:liability)
  end

  def net_worth_at date
    net_worth run_projection date
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
    @projector.add_account(
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
    refute_equal 0, @projector.balance

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
    assert_equal 0, @projector.balance
    assert_equal 500, net_worth_at(dec_31_2000)
  end

  def test_accounts_must_be_balanced_to_run_projection
    @projector.add_account(
      :checking,
      open_date:       jan_1_2000,
      opening_balance: 500,
      type:            :asset,
    )
    refute_equal 0, @projector.balance

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
      date:   jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    results = run_projection dec_31_2000
    assert_equal 1000, net_worth(results)
    assert_equal 1000, results.account_balance(:checking)
    assert_equal 1000, results.account_balance(:nustartup_inc)
  end

  def test_future_transaction
    @projector.add_transaction(
      date: jan_1_2010,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    results = run_projection dec_31_2000
    assert_equal 0,    net_worth(results)
    assert_equal 0,    net_worth(results.project(to: dec_31_2009))
    assert_equal 1000, net_worth(results.project(to: jan_1_2010))
  end

  def test_past_transaction
    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: dec_31_1999,
        credit: [1000, :nustartup_inc],
        debit:  [1000, :checking],
      )
    end
  end

  def test_single_transaction_to_sub_account_without_split
    @projector.split_account :checking, into: %i(checking_sub_1 checking_sub_2)

    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking_sub_1],
    )

    results = run_projection dec_31_2000
    assert_equal 1000, results.account_balance(:checking)
    assert_equal 1000, results.account_balance(:checking_sub_1)
    assert_equal 0,    results.account_balance(:checking_sub_2)
  end

  def test_single_transaction_with_split
    @projector.add_account :savings, type: :asset
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debits: [ [500, :checking], [500, :savings]],
    )

    assert_equal 1000, net_worth_at(dec_31_2000)
  end

  def test_single_transaction_with_split_on_both_sides
    @projector.add_account :savings, type: :asset

    assert_raises Projector::InvalidTransaction do
      @projector.add_transaction(
        date: jan_1_2000,
        credits: [[540, :nustartup_inc], [ 460, :nustartup_inc]],
        debits: [[500, :checking], [500, :savings]],
      )
    end
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

class ProjectorRecurringTransactionTest < ProjectionTest
  def setup
    super
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_recurring_transaction
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(dec_31_2000),
    )
    results = run_projection dec_31_2000
    assert_equal 48000, net_worth(results)
    assert_equal 0,     results.transactions.size
  end

  def test_recurring_transaction_with_prorated_end
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(apr_15_2000),
    )
    results = run_projection dec_31_2000
    assert_equal 14000, net_worth(results)
    assert_equal 0,    results.transactions.size
  end

  def test_recurring_transaction_ending_after_projection
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(dec_31_2001),
    )

    results = run_projection dec_31_2000
    assert_equal 48000, net_worth(results)
    results = results.project to: jun_30_2001
    assert_equal 72000, net_worth(results)
    results = results.project to: dec_31_2001
    assert_equal 96000, net_worth(results)
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
    assert_equal 16000, net_worth_at(dec_31_2000)
  end

  def test_recurring_transaction_after_the_projection_range
    @projector.add_transaction(
      date: feb_1_2001,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(may_31_2001),
    )
    assert_equal 0, net_worth_at(dec_31_2000)
  end

  def test_recurring_transactions_are_processed_in_chronological_order
    @projector.add_transaction(
      date: jan_1_2000,
      credit: [4000, :nustartup_inc],
      debit:  [4000, :checking],
      schedule: every_month(mar_31_2000),
    )
    @projector.add_transaction(
      date: jan_15_2000,
      credit: [400, :nustartup_inc],
      debit:  [400, :checking],
      schedule: every_month(mar_14_2000),
    )
    transaction_dates = []
    run_projection dec_31_2000 do |t| transaction_dates.push t.date; end
    assert_equal [jan_1_2000, jan_15_2000, feb_1_2000, feb_15_2000, mar_1_2000],
      transaction_dates
  end

  def test_recurring_transaction_with_percentages
    @projector.accounts.fetch(:checking).instance_variable_set :@opening_balance, 5000
    @projector.accounts.fetch(:nustartup_inc).instance_variable_set :@opening_balance, 5000
    @projector.add_transaction(
      date:   jan_1_2000,
      credit: [{percent: 20.0, of: :nustartup_inc}, :nustartup_inc],
      debit:  [{percent: 20.0, of: :nustartup_inc}, :checking],
      schedule: every_month(feb_29_2000),
    )

    results = run_projection feb_29_2000
    assert_equal 7200, net_worth(results)
    assert_equal 7200, results.account_balance(:checking)
    assert_equal 7200, results.account_balance(:nustartup_inc)
  end

  def test_recurring_transaction_with_remainder
    @projector.add_account :hsa, type: :asset
    @projector.add_transaction(
      date:   jan_1_2000,
      credit: [4000, :nustartup_inc],
      debits: [[3800, :checking],
               [:remainder, :hsa]],
      schedule: every_month,
    )
    results = run_projection dec_31_2000
    assert_equal 48000, net_worth(results)
    assert_equal 45600, results.account_balance(:checking)
    assert_equal 48000, results.account_balance(:nustartup_inc)
    assert_equal 2400,  results.account_balance(:hsa)
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
    @projector = @old_projector.project to: dec_31_2000
  end

  def test_projection_discards_finished_transactions_on_import
    assert_equal 4, @old_projector.transactions.size
    assert_equal 3, @projector.transactions.size
  end

  def test_from_is_set_to_end_of_projection
    assert_equal jan_1_2001, @projector.from
  end

  def test_accounts_are_setup_with_opening_balances_matching_prior_closing_balances
    assert_equal 50000, @projector.account_balance(:checking)
    assert_equal 50000, @projector.account_balance(:nustartup_inc)
    assert_equal 0,     @projector.account_balance(:big_company_inc)
  end

  def test_next_years_projection
    assert_equal 0, net_worth(@old_projector)
    assert_equal 50000, net_worth(@projector)
    assert_equal 50000 + (24000 + 30000 + 6500), net_worth(@projector.project(to: dec_31_2001))
  end

  private

  def projection
    @projector.project to: dec_31_2001
  end
end

class ProjectorInvestmentTest < ProjectionTest
  def setup
    super
    @projector.accounts = {
      checking:           { type: :asset    },
      investment:         { type: :asset,
                            open_date:        jul_1_2000,
                            subtype:          :investment,
                            annual_interest:  6.000,
                            interest_revenue: :investment_revenue,
                            principal:        :investment,
                          },
      investment_revenue: { type: :revenue, open_date: jul_1_2000 },
    }
  end

  def test_that_investment_receives_compound_interest
    @projector.add_transaction(
      date: jul_1_2000,
      credit: [200000, :checking],
      debit:  [200000, :investment],
    )
    skip
  end

  def test_monthly_contributions
    @projector.add_transaction(
      date: jul_1_2000,
      credit: [1000, :checking],
      debit:  [1000, :investment],
      schedule: every_month,
    )
    skip
  end

  def test_changing_monthly_contributions
    @projector.add_transaction(
      date: jul_1_2000,
      credit: [1000, :checking],
      debit:  [1000, :investment],
      schedule: every_month(may_31_2001),
    )
    @projector.add_transaction(
      date: jun_1_2001,
      credit: [1200, :checking],
      debit:  [1200, :investment],
      schedule: every_month,
    )
    skip
  end
end

class ProjectorSimpleLoanPayoffTest < ProjectionTest
  def test_loan_payoff_on_schedule
    skip
  end

  def test_loan_pays_off_faster_with_extra_principal
    skip
  end
end

class ProjectorDrainAccountTest < ProjectionTest
  def test_putting_all_available_cash_into_an_investment
    skip
  end
end

class MortgageTest < ProjectionTest
  def setup
    skip
    super

    @projector.accounts = {
      checking:          { type: :asset     },
      mortgage:          { type: :liability },
      mortgage_interest: { type: :expense   },
    }

    @projector.transactions = [{
      date: jul_1_2000,
      credit:   [200000, :loan],
      debit:    [200000, :checking],
    },{
      date: jul_1_2000,
      schedule: {
        accounts: {
          interest:  :loan_interest,
          payment:   :checking,
          principal: :loan,
        },
        annual_interest: 3.000,
        months:          360,
        type:            :mortgage,
      },
    }]
  end

  def test_30_year_mortgage
    skip
  end

  def test_15_year_mortgage
    skip
  end

  def test_30_year_mortgage_with_one_time_extra_payment
    skip
  end

  def test_30_year_mortgage_with_extra_principal
    skip
  end
end

__END__

    @projector.accounts = {
      loan:               { type: :liability, },
      loan_interest:      { type: :expense,   },
    }

    @projector.transactions = [{
      date: jul_1_2000,
      credit:   [200000, :loan],
      debit:    [200000, :checking],
    },{
      date: jul_1_2000,
      credit: [200000, :checking],
      debit:  [200000, :investment],
    },{
      date: jul_1_2000,
      schedule: {
        accounts: {
          interest:  :loan_interest,
          payment:   :checking,
          principal: :loan,
        },
        annual_interest: 3.000,
        initial_value:   200000,
        months:          360,
        type:            :mortgage,
      },
    },{
      date: jul_1_2000,
      schedule: {
        accounts: {
          interest:  :investment_revenue,
          payment:   :investment,
          principal: :investment,
        },
        annual_interest: 6.000,
        initial_value:   200000,
        type:            :compound,
      },
    }]
  end
  def test_borrow_at_three_lend_at_six_hit_the_course_nine
    p1 = projection

    expected_balances = expected_dec_31_2000_balances
    %i(investment investment_revenue loan loan_interest checking).each do |account_id|
      expected_balance = expected_balances.fetch account_id
      actual_balance   = p1.account_balance account_id
      assert_equal_balances account_id, expected_balance, actual_balance
    end
    assert_equal_balances :net_worth, expected_2000_net_worth, p1.net_worth

    p2 = Projector.new(p1).project to: jun_30_2015
    p3 = Projector.new(p2).project to: dec_31_2050
    p4 = Projector.new(p2).project to: jun_30_2030

    assert_equal_balances :loan, 0, p3.account_balance(:loan)
    assert_equal_balances :loan, 0, p4.account_balance(:loan)
    assert_equal_balances :investment, investment_value_at(jun_30_2030), p4.account_balance(:investment)
    assert_equal_balances :investment, investment_value_at(dec_31_2050), p3.account_balance(:investment)

    assert_equal_balances :loan_interest, lifetime_loan_interest, p4.account_balance(:loan_interest)
    assert_equal_balances :net_worth, expected_2030_net_worth, p4.net_worth
  end

  def test_extra_principal_each_month
    # Without extra principal
    expected_balances = expected_dec_31_2000_balances
    assert_equal_balances :loan, expected_balances.fetch(:loan), projection.account_balance(:loan)

    # With extra principal
    transaction = @projector.transactions.fetch 2
    transaction.credits.push(amount: 100, account: :checking)
    transaction.debits.push( amount: 100, account: :loan)

    assert_equal_balances :loan, expected_balances.fetch(:loan) - 603.76, projection.account_balance(:loan)

    # Extra principal payments must balance
    transaction.credits.pop
    transaction.debits.pop
    transaction.validate! @projector
    transaction.credits.push(amount: 100, account: :checking)
    transaction.debits.push( amount: 101, account: :loan)
    assert_raises Projector::BalanceError do
      transaction.validate! @projector
    end

    # Extra principal payments must route to the correct accounts
    transaction.credits.pop
    transaction.debits.pop
    transaction.credits.push(amount: 100, account: :checking)
    transaction.debits.push( amount: 100, account: :checking)
    assert_raises Projector::InvalidTransaction do
      transaction.validate! @projector
    end

    # Only mortgages can have extra principal payments
    transaction = @projector.transactions.fetch 3
    transaction.credits.push(amount: 100, account: :checking)
    transaction.debits.push( amount: 100, account: :investment)
    assert_raises Projector::InvalidTransaction do
      transaction.validate! @projector
    end
  end

  private

  def assert_equal_balances account_id, expected, actual
    assert_equal expected.to_d, actual.to_d,
      "Expected #{account_id.inspect} balance to equal "\
      "#{expected.round(2).to_f}, but instead was "\
      "#{actual.round(2).to_f}"
  end

  def expected_dec_31_2000_balances
    loan_amount          = 200000
    loan_interest        = 2987.09.to_d
    loan_principal       = 2072.16.to_d
    investment_amount    = 200000
    investment_interest  = 6075.50.to_d
    {
      checking:           0 - (loan_interest + loan_principal),
      investment:         investment_amount + investment_interest,
      investment_revenue: investment_interest,
      loan:               loan_amount - loan_principal,
      loan_interest:      loan_interest,
    }
  end

  def expected_2000_net_worth
    expected_balances = expected_dec_31_2000_balances
    expected_balances[:investment] + expected_balances[:checking] -
      expected_balances[:loan]
  end

  def expected_2030_net_worth
    investment_value_at(jun_30_2030) - 200000 - 103554.91
  end

  def lifetime_loan_interest
    103554.91
  end

  def investment_value_at date
    months_between = DateDiff.date_diff :month, jul_1_2000, date
    r = 6.0.to_d / 1200
    (200000 * ((1 + r) ** months_between)).round 2
  end
end
