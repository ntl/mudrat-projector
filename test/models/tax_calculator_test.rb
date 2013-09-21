require 'test_helper'

class TaxCalculatorTest < Minitest::Unit::TestCase
  def setup
    @household = OpenStruct.new(
      exemptions: 2,
      filing_status: :married_filing_jointly,
    )
  end

  def test_raises_an_unsupported_year_error_when_year_is_not_supported
    assert_raises TaxCalculator::UnsupportedYear do
      TaxCalculator.new year: 9999
    end
  end

  def creates_an_income_source_breakdown
    @property = OpenStruct.new(
      appraised_value: 306000,
      tax_rate: 2.4139,
    )
    def @property.interest_paid_in_year(year)
      return method_missing(:interest_paid_in_year, year) unless year == 2013
      16216.8
    end
    @expenses = {
      hsa: [2500 / 12.0],
      medical_and_dental: [167.0],
    }
    @income_sources = [{
      name: 'PersonManage',
      annual_gross: 131252.0,
      tax_form: 'w2',
    },{
      name: 'SlickBot',
      annual_gross: 10500.0,
      tax_form: 'w2',
    },{
      name: 'BrainBits',
      annual_gross: 7200.0,
      tax_form: '1099',
    }]
    @tax_calculator = TaxCalculator.new household: @household, year: 2013,
      property: @property, expenses: @expenses, income_sources: @income_sources

    expected = {
      tax_year: 2013,
      gross: { annual: 148952.0, per_month: 12412.67 },
      deductions: {
        above_the_line: 2500.0,
        below_the_line: 23603.33,
        exemptions: 7800.0,
      },
      income_sources: [{
        name: 'PersonManage',
        income_tax: { annual: 16194.27, paycheck: 622.86 },
        medicare: { annual: 1411.56, paycheck: 54.29 },
        ss: { annual: 6035.62, paycheck: 232.14 },
        gross: { annual: 131252.0, paycheck: 5048.15 },
      },{
        name: 'SlickBot',
        income_tax: { annual: 2625.0, paycheck: 656.25 },
        medicare: { annual: 152.25, paycheck: 38.06 },
        ss: { annual: 651.0, paycheck: 162.75 },
        gross: { annual: 10500.0, paycheck: 2625.0 },
      },{
        name: 'BrainBits',
        income_tax: { annual: 1800.0, paycheck: 150.0 },
        medicare: { annual: 192.83, paycheck: 16.07 },
        ss: { annual: 824.50, paycheck: 68.71 },
        gross: { annual: 7200.0, paycheck: 600.0 },
      }],
      net: { annual: 119064.98, per_month: 9922.08 },
    }


    assert_equal_recursively expected, @tax_calculator.breakdown
    assert_equal expected, @tax_calculator.breakdown
  end

  def test_sorts_income_sources_by_w2_1099_then_amount
    income_sources = [{
      name: 'IS #1',
      annual_gross: 12000.0,
      tax_form: '1099',
    },{
      name: 'IS #2',
      annual_gross: 12000.0,
      tax_form: 'w2',
    },{
      name: 'IS #3',
      annual_gross: 6000.0,
      tax_form: 'w2',
    },{
      name: 'IS #4',
      annual_gross: 24000.0,
      tax_form: 'w2',
    }]

    tax_calculator = TaxCalculator.new household: @household, year: 2013,
      income_sources: income_sources

    assert_equal ['IS #4', 'IS #2', 'IS #3', 'IS #1'],
      tax_calculator.income_sources.map(&:name)
  end

  private

  def assert_equal_recursively(expected, other)
    recursive_check = ->(expected, other, stack) {
      expected.each do |k,v|
        stack.push k
        if v.is_a? Hash
          recursive_check.call v, other[k], stack
        elsif v.is_a? Array
          v.each.with_index do |e, index|
            stack.push index
            recursive_check.call e, other[k][index], stack
            stack.pop
          end
        else
          path = stack.each.with_object 'expected' do |node, str|
            if node.is_a? Numeric
              str.concat "[#{node}]"
            else
              str.concat "->#{node}"
            end
          end
          assert_equal v, other[k], "Path: #{path}"
        end
        stack.pop
      end
    }

    recursive_check.call expected, other, Array.new
  end
end

__END__

private

  def expected_2000_taxes income
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
