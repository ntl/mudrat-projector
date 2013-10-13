require 'test_helper'

class MortgageTest < Minitest::Unit::TestCase
  def setup
    @loan_amount       = 200_000
    @home_value        = 250_000
    @down_payment      = @home_value - @loan_amount

    @interest_rate     = 5.0.to_d
    @property_tax_rate = 1.25.to_d
    @loan_term         = 30
    @start_date        = jan_1_2012

    @projector = Projector.new from: jan_1_2012

    @projector.add_account :checking, type: :asset,     opening_balance: 50000
    @projector.add_account :job,      type: :revenue,   opening_balance: 50000
    @projector.add_account :home,     type: :asset,     open_date: feb_1_2012
    @projector.add_account :mortgage, type: :liability, open_date: feb_1_2012
    @projector.add_account :interest, type: :expense

    r  = @interest_rate / 1200
    x  = (1 + r) ** (@loan_term * 12)
    mp = (@loan_amount * r * x) / (x - 1)

    @projector.add_transaction(
      date: feb_1_2012,
      credits: [{ amount: @down_payment, account_id: :checking },
                { amount: @loan_amount,  account_id: :mortgage }],
      debit:    { amount: @home_value,   account_id: :home     },
    )
    @projector.add_transaction(
      date: feb_1_2012,
      credits: [{ percent: r, of: :mortgage, account_id: :mortgage},
                { amount: mp, account_id: :checking }],
      debits:  [{ amount: mp, account_id: :mortgage },
                { percent: r, of: :mortgage, account_id: :interest}],
      schedule: { unit: :month, scalar: 1, count: (@loan_term * 12) },
    )
  end

  def test_balance_after_first_year
    @projector.project to: dec_31_2012
    assert_in_epsilon 197_300.83, @projector.account_balance(:mortgage)
  end

  def test_mortgage_balances_to_zero_at_end_of_term
    @projector.project to: jan_31_2042
    assert_equal 0, @projector.account_balance(:mortgage).round(2).to_f
  end

  def test_pay_off_mortgage_early
  end

end
