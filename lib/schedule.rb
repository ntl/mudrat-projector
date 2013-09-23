class Schedule
  attr :date

  def initialize date
    @date = date
    freeze
  end

  def before? other_date
    date < other_date
  end

  def after? other_date
    date > other_date
  end

  def type
    self.class.to_s.split('::').last.tap do |classified|
      classified.chomp! 'Schedule'
      classified.gsub!(/[A-Z][a-z]/) { |b| "_#{b.downcase}" }
      classified.slice! 0, 1
    end
  end
end

class OneTimeSchedule < Schedule
  def apply! transaction, range, &block
    yield_over_each_bit transaction.credits, transaction.debits, &block
    nil
  end

  def recurring?
    false
  end

  def transaction_balanced? transaction
    credits, debits = total_credits_and_debits transaction
    credits == debits
  end

  private

  def yield_over_each_bit credits, debits, multiplier = 1
    credits.each do |amount, account_id|
      yield :credit, amount * multiplier, account_id
    end
    debits.each do |amount, account_id|
      yield :debit, amount * multiplier, account_id
    end
  end

  def total_credits_and_debits transaction
    credit_amounts = transaction.credits.map &:first
    debit_amounts  = transaction.debits.map  &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    [sum_of.call(credit_amounts), sum_of.call(debit_amounts)]
  end
end

class RecurringSchedule < OneTimeSchedule
  attr :end, :number, :unit
    
  def initialize date, params = {}
    @end    = params[:end] || Projector::ABSOLUTE_END
    @number = params.fetch :number
    @unit   = params.fetch :unit
    super date
  end

  def after? other_date
    date > other_date
  end

  def apply! transaction, range, &block
    yield_over_each_bit(
      transaction.credits,
      transaction.debits,
      calculate_range_multiplier(range),
      &block
    )
    remainder_transaction transaction, range
  end

  def before? other_date
    date < other_date
  end

  def to_hash
    {
      end:    self.end,
      number: number,
      type:   :recurring,
      unit:   unit,
    }
  end

  def recurring?
    true
  end

  private

  def calculate_range_multiplier range
    txn_start = [range.begin, date].max
    txn_end   = [range.end, self.end].min
    DateDiff.date_diff(unit: unit, from: txn_start, to: txn_end) * (1.0 / number)
  end

  def remainder_transaction transaction, range
    return nil if self.end <= range.end
    Transaction.new(
      date:     range.end + 1,
      credits:  transaction.credits,
      debits:   transaction.debits,
      schedule: to_hash,
    )
  end
end

class CompoundSchedule < Schedule
  attr :annual_interest, :initial_value

  class CompoundResult
    attr :balance, :end, :range

    def initialize params = {}
      @balance          = params.fetch :balance
      @range            = params.fetch :range
      @interest         = params.fetch :interest
      @principal        = params.fetch :principal, 0
    end

    def inspect
      { balance: balance.to_f, range: range, interest: interest.to_f, principal: principal.to_f}.inspect
    end

    def interest
      @interest.round 2
    end

    def next_transaction transaction, schedule
      Transaction.new(
        date:     range.end + 1,
        credits:  transaction.credits,
        debits:   transaction.debits,
        schedule: schedule,
      )
    end

    def principal
      @principal.round 2
    end

    def payment
      interest + principal
    end

    def yield_over_each_bit credits, debits, &block
      decode_amount_key = {
        interest:  interest,
        principal: principal,
        payment:   payment,
      }
      credits.each do |credit|
        amount = decode_amount_key.fetch credit.fetch :amount
        yield :credit, amount, credit.fetch(:account)
      end
      debits.each do |debit|
        amount = decode_amount_key.fetch debit.fetch :amount
        yield :debit, amount, debit.fetch(:account)
      end
    end
  end

  class MortgageResult < CompoundResult
    attr :months_amortized
    def initialize params = {}
      super
      @months_amortized = params.fetch :months_amortized
    end
  end

  def initialize date, params = {}
    @annual_interest = params.fetch :annual_interest
    @initial_value   = params.fetch :initial_value
    super date
  end

  def apply! transaction, range, &block
    result = Projector.with_banker_rounding { amortize range }
    result.yield_over_each_bit transaction.credits, transaction.debits, &block
    return nil if result.balance.zero?
    result.next_transaction transaction, next_schedule(result)
  end

  def monthly_payment
    iv  = initial_value
    r   = rate
    n   = months
    (iv * r) / (1 - ((1 + r) ** (-n)))
  end

  def rate
    annual_interest.to_d / 1200
  end

  def transaction_balanced? transaction
    true
  end

  private

  def amortize range
    months_amortized = DateDiff.date_diff(:month, [range.begin, date].max, range.end).to_i
    new_balance = initial_value * ((1 + rate) ** months_amortized)
    interest_paid  = new_balance - initial_value
    CompoundResult.new(
      range: range,
      balance: new_balance, 
      interest: interest_paid
    )
  end

  def next_schedule result
    {
      annual_interest: annual_interest,
      initial_value:   result.balance,
      type:            type,
    }
  end
end

class MortgageSchedule < CompoundSchedule
  attr :months

  def initialize date, params = {}
    @months = params.fetch :months
    super date, params
  end

  def final_month
    (date >> months) - 1
  end

  private

  def amortize range, &block
    r  = rate
    mp = monthly_payment

    range_begin = [range.begin, date].max
    range_end   = [range.end,   final_month].min
    months_to_amortize = DateDiff.date_diff(:month, range_begin, range_end).to_i

    interest_paid  = 0
    principal_paid = 0

    new_balance = months_to_amortize.times.inject initial_value do |balance, _|
      interest    = balance * r
      principal   = mp - interest
      interest_paid  += interest
      principal_paid += principal
      balance - principal
    end

    new_months = months - months_to_amortize

    MortgageResult.new(
      range: range,
      months_amortized: months_to_amortize, 
      balance: new_balance,
      interest: interest_paid,
      principal: principal_paid,
    )
  end

  def next_schedule result
    super.tap do |hash|
      hash[:months] = months - result.months_amortized
    end
  end
end
