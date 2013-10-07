require 'test_helper'

__END__

class TaxCalculatorShelleyTest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2013
    @projector.accounts = {
      checking:     { type: :asset,    opening_balance: 50000 },
      w2_job:       { type: :revenue,  tags: %i(w2)},
      charity:      { type: :expense,  tags: %i(501c)},
      hsa:          { type: :asset,    tags: %i(hsa individual)},
      se_expenses:  { type: :expense,  tags: %i(self_employed)},
      se_job:       { type: :revenue,
                      opening_balance: 50000,
                      tags: %i(self_employed)},
    }
  end

  # http://taxes.about.com/od/paymentoptions/a/estimated_tax_3.htm
  def test_shelley
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [25000 / 3.0, :se_job],
      debit:    [25000 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    },{
      date:     jan_1_2013,
      credit:   [7500 / 3.0, :checking],
      debit:    [7500 / 3.0, :se_expenses],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate single_household
    assert_equal 2013, tax_calculation.year
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 19583
  end

  def test_shelly_2012
    @projector.instance_variable_set :@from, jan_1_2012

    @projector.transactions = [{
      date:     jan_1_2012,
      credit:   [17500 / 3.0, :se_job],
      debit:    [17500 / 3.0, :checking],
      schedule: every_month(dec_31_2012),
    }]

    tax_calculation = calculate single_household
    assert_equal 2012, tax_calculation.year
    # shoudl be lower, see http://en.wikipedia.org/wiki/Tax_Relief,_Unemployment_Insurance_Reauthorization,_and_Job_Creation_Act_of_2010
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 18514
  end

  def test_shelley_as_salaried_without_workplace_deductions
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [17500 / 3.0, :w2_job],
      debit:    [17500 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate single_household
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 16284
  end

  def test_married_filing_jointly_with_two_kids
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [17500 / 3.0, :w2_job],
      debit:    [17500 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 10793
  end

  def test_social_security_wage_base
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [10000, :w2_job],
      debit:    [10000, :checking],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 120000, taxes: 23696.9
  end

  def test_mix_of_salaried_and_self_employed
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [10000, :w2_job],
      debit:    [10000, :checking],
      schedule: every_month(dec_31_2013),
    },{
      date:     jan_1_2013,
      credit:   [800, :se_job],
      debit:    [800, :checking],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 129600, taxes: 27284.10
  end

  def test_itemized_deductions
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [17500 / 3.0, :w2_job],
      debit:    [17500 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    },{
      date:     jan_1_2013,
      credit:   [1500, :checking],
      debit:    [1500, :charity],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 9922.5
  end

  def test_hsa_above_the_line_deduction
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [17500 / 3.0, :w2_job],
      debit:    [17500 / 3.0, :checking],
      schedule: every_month(dec_31_2013),
    },{
      date:     jan_1_2013,
      credit:   [300, :checking],
      debit:    [300, :hsa],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 70000, taxes: 10305
  end

  def test_hsa_pretax_deduction
    @projector.accounts[:hsa].instance_variable_set :@tags, %i(hsa family senior)
    @projector.transactions = [{
      date:     jan_1_2013,
      credit:   [10000, :w2_job],
      debits:   [[9000, :checking],
                 [1000, :hsa]],
      schedule: every_month(dec_31_2013),
    }]

    tax_calculation = calculate married_two_kids_household
    assert_tax_calculation tax_calculation, gross: 120000, taxes: 21655
  end

  def test_mortgage_interest_and_property_taxes
    skip
  end

  def test_alternative_minimum
    skip
  end
  
  private

  def calculate household
    tax_calculator = TaxCalculator.new(
      household: household,
      projector: @projector,
    )
    tax_calculator.project
  end

  def married_two_kids_household
    TaxCalculator::Household.new :married_filing_jointly, 4
  end

  def single_household
    TaxCalculator::Household.new :single, 1
  end

  def assert_tax_calculation tax_calculation, gross: 0, taxes: 0
    expected_net  = gross - taxes
    expected_rate = ((taxes * 100.0) / gross).round 2

    assert_in_delta gross,         tax_calculation.gross,          1
    assert_in_delta taxes,         tax_calculation.taxes,          1
    assert_in_delta expected_net,  tax_calculation.net,            1
    assert_in_delta expected_rate, tax_calculation.effective_rate, 0.01
  end
end
