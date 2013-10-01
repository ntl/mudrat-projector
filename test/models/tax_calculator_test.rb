require 'test_helper'

class TaxCalculatorTest < Minitest::Unit::TestCase
  # http://taxes.about.com/od/paymentoptions/a/estimated_tax_3.htm
  def test_shelley
    projector = Projector.new from: jan_1_2013
    projector.accounts = {
      checking:     { type: :asset,   },
      biz_expenses: { type: :expense, tags: %i(business)},
      job:          { type: :revenue, tags: %i(self_employed)},
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

    assert_equal 2013,     tax_calculation.year
    assert_equal 70000,    tax_calculation.gross
    assert_equal 19583.19, tax_calculation.taxes
    assert_equal 50416.81, tax_calculation.net
    assert_equal 27.98,    tax_calculation.effective_rate
  end
end

__END__

  def setup
    @projector = Projector.new from: jan_1_2000
    @projector.accounts = {
      checking:           { type: :asset,     },
      investment:         { type: :asset,     },
      investment_revenue: { type: :revenue,   },
      job:                { type: :revenue,   },
      mortgage:           { type: :liability, },
      mortgage_interest:  { type: :expense,   },
    }
    @projector.transactions = [{
      date:   jan_1_2000,
      credit: [4000, :job],
      debit:  [4000, :checking],
      schedule: every_month,
    }]
  end

  def test_year_2000_single
    @household = TaxCalculator::Household.new :single, 1

    assert_equal 2000,    tax_calculator.year
    assert_equal 48000,   tax_calculator.gross
    assert_equal 39988.5, tax_calculator.net
    assert_equal 8011.5,  tax_calculator.taxes
  end

  def test_year_2000_married_jointly
    skip
    @household = TaxCalculator::Household.new :married_jointly, 2

    assert_equal 2000,    tax_calculator.year
    assert_equal 48000,   tax_calculator.gross
    assert_equal 39988.5, tax_calculator.net
    assert_equal 8011.5,  tax_calculator.taxes
  end
  private

  def tax_calculator
    TaxCalculator.new(projector: @projector, household: @household).project
  end
end
