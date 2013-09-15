require 'test_helper'

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
