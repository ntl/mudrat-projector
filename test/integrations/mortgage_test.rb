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
    @projector.add_account :interest, type: :expense,   open_date: feb_1_2012

    @projector.add_transaction(
      date: jan_1_2012,
      credit: { amount: 6000, account_id: :job },
      debit:  { amount: 6000, account_id: :checking },
      schedule: { unit: :month, scalar: 1 },
    )

    @projector.add_transaction(
      date: feb_1_2012,
      credits: [{ amount: @down_payment, account_id: :checking },
                { amount: @loan_amount,  account_id: :mortgage }],
      debit:    { amount: @home_value,   account_id: :home     },
    )
  end

  def test_balance_after_first_year
    pay_off_loan years: 30
    @projector.project to: dec_31_2012
    assert_in_epsilon 197_300.83, @projector.account_balance(:mortgage).to_f
  end

  def test_net_worth_after_first_year
    skip
    pay_off_loan years: 30
    @projector.project to: dec_31_2012
    assert_in_epsilon ((72000 + 250000 - 9110.90) - 197_300.83), @projector.net_worth.round(2).to_f
  end

  def test_mortgage_balances_to_zero_at_end_of_term
    pay_off_loan years: 30
    @projector.project to: jan_31_2042
    assert_equal 0, @projector.account_balance(:mortgage).round(2).to_f
  end

  def test_pay_off_mortgage_early
    pay_off_loan years: 15
    @projector.project to: jan_31_2027
    assert_in_epsilon 0, @projector.account_balance(:mortgage)
  end

  private

  def calculate_monthly_payment r, years = @loan_term
    x  = (1 + r) ** (years * 12)
    mp = (@loan_amount * r * x) / (x - 1)
  end

  def pay_off_loan years: @loan_term
    r  = @interest_rate / 1200
    mp = calculate_monthly_payment r, years

    @projector.add_transaction(
      date: feb_1_2012,
      credits: [{ percent: r, of: :mortgage, account_id: :mortgage},
                { amount: mp, account_id: :checking }],
      debits:  [{ amount: mp, account_id: :mortgage },
                { percent: r, of: :mortgage, account_id: :interest}],
      schedule: { unit: :month, scalar: 1, count: (years * 12) },
    )
  end
end
