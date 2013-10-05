require 'test_helper'

class TaxCalculatorShelleyTest < Minitest::Unit::TestCase
  # http://taxes.about.com/od/paymentoptions/a/estimated_tax_3.htm
  def test_shelley
    projector = Projector.new from: jan_1_2013
    projector.accounts = {
      checking:     { type: :asset,   opening_balance: 50000 },
      biz_expenses: { type: :expense, tags: %i(business)},
      job:          { type: :revenue,
                      opening_balance: 50000,
                      tags: %i(self_employed)},
    }
    projector.transactions = [{
      date:     jan_1_2013,
      credit:   [25000 / 3.0, :job],
      debit:    [25000 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    },{
      date:     jan_1_2013,
      credit:   [7500 / 3.0, :checking],
      debit:    [7500 / 3.0, :biz_expenses],
      schedule: every_month(dec_31_2013),
    }]

    household = TaxCalculator::Household.new :single, 1
    tax_calculator = TaxCalculator.new(
      household: household,
      projector: projector,
    )
    tax_calculation = tax_calculator.project

    assert_equal 2013,  tax_calculation.year
    assert_equal 70000, tax_calculation.gross
    assert_equal 19583, tax_calculation.taxes.round
    assert_equal 50417, tax_calculation.net.round
    assert_equal 27.98, tax_calculation.effective_rate
  end
end

class TaxCalculatorTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2012
    @projector.accounts = {
      checking:     { type: :asset,   opening_balance: 50000 },
      biz_expenses: { type: :expense, tags: %i(business)},
      job:          { type: :revenue, opening_balance: 50000, tags: %i(w2)},
    }
    @projector.transactions = [{
      date:     jan_1_2012,
      credit:   [4000, :job],
      debit:    [4000, :checking],
      schedule: every_month(dec_31_2012),
    }]
  end

  def test_itemized_deductions_exceed_standard
    skip
  end

  def test_married_household_with_salaried_income
    household = TaxCalculator::Household.new :married_filing_jointly, 2
    tax_calculator = TaxCalculator.new(
      household: household,
      projector: @projector,
    )
    tax_calculation = tax_calculator.project

    assert_equal 48000, tax_calculation.gross
    # FAIL: go do the calculation for this
    assert_equal 10000, tax_calculation.taxes.round
  end

  def test_combination_of_self_employed_and_salaried_income
    skip
  end

  def test_returns_projection_decorated_with_tax_withholdings
    skip
  end
end
