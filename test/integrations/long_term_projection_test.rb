require 'test_helper'

class LongTermProjectiontest < Minitest::Unit::TestCase
  def setup
    @projector = Projector.new from: jan_1_2012
    @projector.add_account :checking,   type: :asset
    @projector.add_account :job,        type: :revenue, tags: %i(salary)
    @projector.add_account :investment, type: :asset
    @projector.add_account :dividends,  type: :revenue, tags: %i(dividend)

    @projector.add_transaction(
      date: jan_1_2012,
      credit: { amount: 6000, account_id: :job },
      debit:  { amount: 6000, account_id: :checking },
      schedule: every_month,
    )
    @projector.add_transaction(
      date: jan_1_2012,
      credit: { percent: (6 / 1200.to_d), of: :investment, account_id: :dividends },
      debit:  { percent: (6 / 1200.to_d), of: :investment, account_id: :investment },
      schedule: every_month,
    )
    @projector.add_transaction(
      date: jan_1_2012,
      credit: { amount: 500, account_id: :checking },
      debit:  { amount: 500, account_id: :investment },
      schedule: every_month,
    )

    @household = { filing_status: :single, exemptions: 1 }
  end

  def test_two_years
    projector = TaxCalculator.project @projector, to: dec_31_2013, household: @household

    # used http://investor.gov/tools/calculators/compound-interest-calculator
    assert_in_epsilon 715.98, projector.account_balance(:dividends)
    expected_gross = 72000 + 72000 + 715.98
    expected_taxes = 15702.45 + 17073.80
    assert_in_epsilon expected_gross - expected_taxes, projector.net_worth
  end
end
