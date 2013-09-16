require 'test_helper'

class ProjectionTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new
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

  def projection
    @projector.project from: jan_1_2000, to: dec_31_2000
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
    assert_equal Date.new(1970, 1, 1), @projector.accounts[:checking].open_date
  end

  def test_add_accounts_passes_account_hashes_to_add_account
    assert_equal 0, @projector.accounts.size
    @projector.accounts = { checking: { type: :asset } }
    assert_equal 1, @projector.accounts.size
  end

  def test_opening_balances_in_accounts_affects_opening_equity
    assert_equal 0, projection.opening_equity
    @projector.add_account :checking, type: :asset, opening_balance: 50
    assert_equal 50, projection.opening_equity
    @projector.add_account :savings, type: :asset, opening_balance: 90,
      open_date: Date.new(2000, 1, 2)
    assert_equal 50, projection.opening_equity

    assert_equal 140, projection.closing_equity
  end
end

class ProjectorSingleTransactionTest < ProjectionTest
  def setup
    super
    @projector.add_account :checking, type: :asset
    @projector.add_account :nustartup_inc, type: :revenue
  end

  def test_single_transaction_without_split
    assert_equal 0, projection.closing_equity

    @projector.add_transaction(
      date: jan_1_2000,
      credit: [1000, :nustartup_inc],
      debit:  [1000, :checking],
    )

    assert_equal 1000, projection.closing_equity
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
end

__END__

class ProjectorTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new
    @projector.accounts = [{
      id:   :checking,
      name: 'Checking',
      type: :asset,
    }]

    @projector.tax_info = {
      2000 => { filing_status: :single, exemptions: 1 },
      2001 => { filing_status: :single, exemptions: 1 },
      2002 => { filing_status: :single, exemptions: 1 },
      2003 => { filing_status: :married_filing_jointly, exemptions: 2 },
      2004 => { filing_status: :married_filing_jointly, exemptions: 2 },
      2005 => { filing_status: :married_filing_jointly, exemptions: 3 },
      2006 => { filing_status: :married_filing_jointly, exemptions: 3 },
      2007 => { filing_status: :married_filing_jointly, exemptions: 3 },
      2008 => { filing_status: :married_filing_jointly, exemptions: 4 },
      2009 => { filing_status: :married_filing_jointly, exemptions: 4 },
    }
  end

  def test_simple_projection
    assert_equal 0, projection.net_worth

    @projector.transactions.push(
      amount:  50000.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      recurring_schedule: [1, :year],
    )

    assert_equal 500000, projection.net_worth
    assert_equal 1000000, projection(Date.new(2019, 12, 31)).net_worth

    @projector.transactions.push(
      amount:  -100.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      recurring_schedule: [1, :month],
    )
    assert_equal 488000, projection.net_worth
  end

  def test_deducts_income_taxes
    @projector.transactions.push(
      amount:  50000.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      tags: %i(income w2),
      recurring_schedule: [1, :year],
    )
    projection_2000 = projection Date.new(2000, 12, 31)
    assert_equal 50000, projection_2000.gross_revenue
    assert_equal 50000 - expected_2000_taxes, projection_2000.net_revenue
    assert_equal 50000 - expected_2000_taxes, projection_2000.net_worth

    projection_2003 = projection Date.new(2003, 12, 31), start: Date.new(2003, 1, 1)
    assert_equal 50000, projection_2003.gross_revenue
    assert_equal 50000 - expected_2003_taxes, projection_2003.net_revenue
    assert_equal 50000 - expected_2003_taxes, projection_2003.net_worth

    @projector.transactions.push(
      amount:  1000.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      tags: %i(income 1099),
      recurring_schedule: [1, :month],
    )

    projection_2005 = projection Date.new(2005, 12, 31), start: Date.new(2005, 1, 1)
    assert_equal 62000, projection_2005.gross_revenue
    assert_equal 62000 - expected_2005_taxes, projection_2005.net_revenue
    assert_equal 62000 - expected_2005_taxes, projection_2005.net_worth
  end

  def test_projection_with_initial_equity
    @projector.accounts.first[:initial_balance] = 100000
    assert_equal 100000, projection.net_worth

    @projector.transactions.push(
      amount:  50000.0,
      date:    Date.new(2000, 1, 1),
      account: :checking,
      recurring_schedule: [1, :year],
    )
    assert_equal 600000, projection.net_worth
  end

  def test_projection_with_transaction_starting_and_ending_within_timeframe
    @projector.transactions.push(
      amount:   50000.0,
      date:     Date.new(2001, 1, 1),
      end_date: Date.new(2008, 12, 31),
      account:  :checking,
      recurring_schedule: [1, :year],
    )

    assert_equal 400000, projection.net_worth
  end

  private

  def expected_2000_taxes
    income = 50000
    
    agi    = income
    agi   -= 2800 * 1            # Exemption
    agi   -= 4400                # Standard deduction

    [
      26250 * 0.15,              # FICA Bracket 1
      (agi - 26250) * 0.28,      # FICA Bracket 2
      (income * (1.45 / 100.0)), # Medicare
      (income * (6.20 / 100.0)), # SS
    ].inject { |s,v| s + v }
  end

  def expected_2003_taxes
    income = 50000

    agi    = income
    agi   -= 3050 * 2            # Exemption
    agi   -= 9500                # Standard deduction
    [
      14000 * 0.10,              # FICA Bracket 1
      (agi - 14000) * 0.15,      # FICA Bracket 2
      (income * (1.45 / 100.0)), # Medicare
      (income * (6.20 / 100.0)), # SS
    ].inject { |s,v| s + v }
  end

  def expected_2005_taxes
    w2_income = 50000
    se_income = 1000 * 12
    income = w2_income + se_income

    medicare    = income * (1.45 / 100.0)
    ss          = income * (6.20 / 100.0)
    se_medicare = se_income * (1.45 / 100.0)
    se_ss       = se_income * (6.20 / 100.0)

    agi  = income
    agi -= (3200 * 3)                          # Exemption
    agi -= 10000                               # Standard deduction
    agi -= (se_medicare + se_ss)               # Self employed FICA

    [
      14600 * 0.10,                            # FICA Bracket 1 (w2)
      (agi - 14600) * 0.15,                    # FICA Bracket 2 (w2)
      medicare,
      ss,
      se_medicare,
      se_ss,
    ].inject { |s,v| s + v }
  end

  def projection date = Date.new(2009, 12, 31), start: Date.new(2000, 1, 1)
    @projector.project!(
      from: start,
      to: date,
    )
  end
end
