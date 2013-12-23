require 'test_helper'

class ProjectorTest < Minitest::Test
  def setup
    @projector = Projector.new from: jan_1_2000
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_next_projector_includes_deferred_transactions_from_projector
    @projector.add_transaction(
      date: jan_1_2000,
      debit:  { amount: 1000, account_id: :checking },
      credit: { amount: 1000, account_id: :nustartup_inc },
      schedule: every_month(until: jun_30_2001),
    )
    next_projector = @projector.project to: dec_31_2000, build_next: true
    assert_equal jan_1_2001, next_projector.from
    next_projector.project to: dec_31_2001

    assert_equal 18000, next_projector.net_worth
  end

  def test_project_yields_to_block
    @projector.add_transaction(
      date: jan_1_2000,
      debit:  { amount: 1000, account_id: :checking },
      credit: { amount: 1000, account_id: :nustartup_inc },
      schedule: every_month(until: apr_30_2000),
    )

    expected_dates = [jan_1_2000, feb_1_2000, mar_1_2000, apr_1_2000]
    actual_dates = []

    @projector.project to: dec_31_2000 do |transaction|
      actual_dates.push transaction.date
    end

    assert_equal expected_dates, actual_dates
  end
end

class ProjectorAccountsTest < Minitest::Test
  def setup
    @projector = Projector.new from: jan_1_2000
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

  def test_supplying_an_opening_balance
    assert_equal 0, @projector.net_worth

    @projector.add_account(
      :checking,
      open_date:       jan_1_2000,
      opening_balance: 500,
      type:            :asset,
    )
    refute_equal 0, @projector.balance

    assert_raises Projector::InvalidAccount do
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
    assert_equal 500, @projector.net_worth
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
    assert_equal [], @projector.accounts
    @projector.accounts = { checking: { type: :asset } }
    assert_equal [:checking], @projector.accounts
  end
end

class ProjectorTransactionTest < Minitest::Test
  def setup
    @projector = Projector.new from: jan_1_2000
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_single_transaction
    add_simple_transaction

    @projector.project to: dec_31_2000

    assert_equal 1000, @projector.net_worth
    assert_equal 1000, @projector.account_balance(:checking)
    assert_equal 1000, @projector.account_balance(:nustartup_inc)
  end

  def test_scheduled_transaction
    add_scheduled_transaction

    @projector.project to: dec_31_2000

    assert_equal 12000, @projector.net_worth
    assert_equal 12000, @projector.account_balance(:checking)
    assert_equal 12000, @projector.account_balance(:nustartup_inc)
  end

  def test_future_transaction
    add_simple_transaction jan_1_2010

    @projector.project to: dec_31_2000

    assert_equal 0, @projector.net_worth
  end

  def test_annual_transactions_by_12_months
    @projector.add_transaction(
      date: apr_1_2012,
      credit: { amount: 50000, account_id: :nustartup_inc },
      debit:  { amount: 50000, account_id: :checking      },
      schedule: { scalar: 12, unit: :month },
    )

    @projector.project to: mar_31_2042

    assert_equal 1500000, @projector.net_worth
  end

  private

  def add_scheduled_transaction date = jan_1_2000
    @projector.add_transaction(
      date: date,
      credit: { amount: 1000, account_id: :nustartup_inc },
      debit:  { amount: 1000, account_id: :checking      },
      schedule: every_month,
    )
  end

  def add_simple_transaction date = jan_1_2000
    @projector.add_transaction(
      date: date,
      credit: { amount: 1000, account_id: :nustartup_inc },
      debit:  { amount: 1000, account_id: :checking      },
    )
  end
end
