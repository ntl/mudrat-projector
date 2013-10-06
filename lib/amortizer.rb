class Amortizer
  attr :balance, :projection_range
end

class CompoundInterestAmortizer < Amortizer
  attr :schedule

  def initialize schedule, projection_range, **params
    @schedule         = schedule
    @projection_range = projection_range
    @balance, @interest, @principal = amortize
  end

  def amortize
    balance  = initial_value * ((1 + rate) ** months_amortized)
    interest = balance - initial_value
    [balance, interest, 0]
  end

  def each_entry &block
    [[:credit, interest,  schedule.interest_account ],
     [:credit, principal, schedule.principal_account],
     [:debit,  payment,   schedule.payment_account  ]].each &block
  end

  def initial_value
    schedule.initial_value
  end

  def interest
    @interest.round 2
  end

  def months_amortized
    start  = [projection_range.begin, schedule_range.begin].max
    finish = [projection_range.end,   schedule_range.end].min
    DateDiff.date_diff(:month, start, finish).to_i
  end

  def next_transaction transaction, schedule
    Transaction.new(
      date:     projection_range.end + 1,
      credits:  transaction.credits,
      debits:   transaction.debits,
      schedule: schedule,
    )
  end

  def rate
    schedule.rate
  end

  def principal
    @principal.round 2
  end

  def payment
    interest + principal
  end

  def schedule_range
    schedule.range
  end
end

class MortgageAmortizer < CompoundInterestAmortizer
  attr :extra_principal, :monthly_payment

  def initialize *args, extra_principal: 0
    @extra_principal = extra_principal
    super
  end

  def monthly_payment
    schedule.monthly_payment
  end

  def each_entry &block
    [[:credit, interest,  schedule.payment_account  ],
     [:credit, principal, schedule.payment_account  ],
     [:debit,  interest,  schedule.interest_account ],
     [:debit,  principal, schedule.principal_account]].each &block
  end

  def amortize
    interest_paid  = 0
    principal_paid = 0
    
    mp = monthly_payment

    new_balance = months_amortized.times.inject initial_value do |balance, _|
      interest    = balance * rate
      principal   = (mp - interest) + extra_principal
      interest_paid  += interest
      principal_paid += principal
      balance - principal
    end
    
    [new_balance, interest_paid, principal_paid]
  end
end
