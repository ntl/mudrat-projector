require 'test_helper'

class TaxCalculatorTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2012
    @projector.add_account :checking, type: :asset
    @projector.add_account :job,      type: :revenue, tags: %i(salary)

    @projector.add_transaction(
      date: jan_1_2012,
      credit: { amount: 6000, account_id: :job },
      debit:  { amount: 6000, account_id: :checking },
      schedule: every_month,
    )
    @projector.add_transaction(
      date: jun_30_2013,
      credit: { amount: 3000, account_id: :job },
      debit:  { amount: 3000, account_id: :checking },
    )
  end

  def test_basic_1040
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 2012,    calculation.year
    assert_equal 72000,   calculation.gross
    assert_equal 5950,    calculation.deduction
    assert_equal 3800,    calculation.exemption
    assert_equal 4068,    calculation.withholding_tax
    assert_equal 62250,   calculation.taxable_income
    assert_equal 11592.5, calculation.income_tax
    assert_equal 15660.5, calculation.taxes
    assert_equal 56339.5, calculation.net
    assert_equal 21.75,   calculation.effective_rate
  end

  def test_basic_1040_married
    @tax_calculator = TaxCalculator.new projector: @projector, household: married
    calculation = @tax_calculator.calculate!

    assert_equal 11900,  calculation.deduction
    assert_equal 3800*4, calculation.exemption
  end

  def test_basic_1040_2013
    @projector = @projector.project to: dec_31_2012, build_next: true
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 75000,    calculation.gross
    assert_equal 5737.5,   calculation.withholding_tax
  end

  def test_hsa_deduction
  end

  def test_pretax_hsa_deduction
  end

  private

  def single
    { filing_status: :single, exemptions: 1 }
  end

  def married
    { filing_status: :married_filing_jointly, exemptions: 4 }
  end
end
