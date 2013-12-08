require 'test_helper'

# http://taxes.about.com/od/paymentoptions/a/estimated_tax_3.htm
class SelfEmployedTaxCalculationTest < Minitest::Test
  def setup
    @projector = Projector.new from: jan_1_2013

    @projector.accounts = {
      checking:     { type: :asset },
      se_expenses:  { type: :expense, tags: %i(self_employed) },
      se_job:       { type: :revenue, tags: %i(self_employed) },
    }

    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   { amount: 25000 / 3.0.to_d, account_id: :se_job    },
      debit:    { amount: 25000 / 3.0.to_d, account_id: :checking  },
      schedule: every_month,
    },{
      date:     jan_1_2013,
      credit:   { amount: 7500 / 3.0.to_d, account_id: :checking    },
      debit:    { amount: 7500 / 3.0.to_d, account_id: :se_expenses },
      schedule: every_month,
    }]
  end

  def test_shelley
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!
    assert_in_epsilon 70000,    calculation.total_income
    assert_in_epsilon 9890.685, calculation.self_employment_tax
    assert_in_epsilon 4945.34,  calculation.adjustments
    assert_in_epsilon 65054.66, calculation.agi
    assert_in_epsilon 55054.66, calculation.taxable_income 
    assert_in_epsilon 9692.50,  calculation.income_tax
    assert_in_epsilon 19583.19, calculation.taxes
  end

  private

  def single
    { filing_status: :single, exemptions: 1 }
  end
end
