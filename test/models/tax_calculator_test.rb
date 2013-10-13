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
    assert_equal 72000,   calculation.total_income
    assert_equal 0,       calculation.adjustments
    assert_equal 72000,   calculation.agi
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

  def test_charity_contribution
    @projector.add_account :public_radio, type: :expense, tags: %i(501c)
    @projector.add_transaction(
      date: jun_30_2012,
      debit:  { amount: 15000, account_id: :public_radio },
      credit: { amount: 15000, account_id: :checking },
    )
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 15000, calculation.deduction
  end

  def test_basic_1040_2013
    @projector = @projector.project to: dec_31_2012, build_next: true
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 75000,  calculation.total_income
    assert_equal 5737.5, calculation.withholding_tax
  end

  def test_hsa_deduction
    @projector.add_account :hsa, type: :asset, tags: %i(hsa individual)
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    @projector.add_transaction(
      date: jun_30_2012,
      debit:  { amount: 4000, account_id: :hsa },
      credit: { amount: 4000, account_id: :checking },
    )
    calculation = @tax_calculator.calculate!

    assert_equal 72000, calculation.gross
    assert_equal 72000, calculation.total_income
    assert_equal 3100,  calculation.adjustments
    assert_equal 68900, calculation.agi
  end

  def test_pretax_hsa_deduction
    @projector.add_account :hsa, type: :asset, tags: %i(hsa family)
    @projector.add_transaction(
      date: jun_30_2012,
      debit:  { amount: 7000, account_id: :hsa },
      credit: { amount: 7000, account_id: :job },
    )
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 79000, calculation.gross
    assert_equal 72000, calculation.total_income
    assert_equal 0,     calculation.adjustments
    assert_equal 72000, calculation.agi
  end

  def test_mortgage_interest_and_property_taxes_paid
    @projector.add_account :interest, type: :expense, tags: %i(mortgage_interest)
    @projector.add_account :property_taxes, type: :expense, tags: %i(property tax)
    @projector.add_transaction(
      date: jun_30_2012,
      debit:  { amount: 7500, account_id: :interest },
      credit: { amount: 7500, account_id: :job },
    )
    @projector.add_transaction(
      date: jun_30_2012,
      debit:  { amount: 5000, account_id: :property_taxes },
      credit: { amount: 5000, account_id: :job },
    )
    @tax_calculator = TaxCalculator.new projector: @projector, household: single
    calculation = @tax_calculator.calculate!

    assert_equal 12500, calculation.deduction
  end

  private

  def single
    { filing_status: :single, exemptions: 1 }
  end

  def married
    { filing_status: :married_filing_jointly, exemptions: 4 }
  end
end
