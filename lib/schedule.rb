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

  def validate! transaction
    unless transaction_balanced? transaction
      raise Projector::BalanceError, "Debits and credits do not balance"
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
  attr :account_map, :annual_interest, :initial_value

  def initialize date, params = {}
    @annual_interest = params.fetch :annual_interest
    @initial_value   = params.fetch :initial_value
    @account_map     = params.fetch :accounts
    super date
  end

  def apply! transaction, projection_range, &block
    amortizer = build_amortizer transaction, projection_range
    yield_for_each_bit_on_amortizer amortizer, &block
    return nil if amortizer.balance.zero?
    amortizer.next_transaction transaction, next_schedule(amortizer)
  end

  def build_amortizer transaction, projection_range
    Projector.with_banker_rounding do
      CompoundInterestAmortizer.new self, projection_range
    end
  end

  def interest_account
    account_map.fetch :interest
  end

  def final_month
    Projector::ABSOLUTE_END
  end

  def next_schedule result
    {
      accounts:        account_map,
      annual_interest: annual_interest,
      initial_value:   result.balance,
      type:            type,
    }
  end

  def payment_account
    account_map.fetch :payment
  end

  def principal_account
    account_map.fetch :principal
  end

  def range
    (date..final_month)
  end

  def rate
    annual_interest.to_d / 1200
  end

  def validate! transaction
    unless transaction.credits_and_debits.empty?
      raise Projector::InvalidTransaction, "You cannot supply extra debit or "\
        "credits on a compound interest schedule"
    end
  end

  def yield_for_each_bit_on_amortizer amortizer
    yield :credit, amortizer.interest,  interest_account
    yield :credit, amortizer.principal, principal_account
    yield :debit,  amortizer.payment,   payment_account
  end
end

class MortgageSchedule < CompoundSchedule
  attr :months

  def initialize date, params = {}
    @months = params.fetch :months
    super date, params
  end

  def build_amortizer transaction, projection_range
    Projector.with_banker_rounding do
      MortgageAmortizer.new(
        self,
        projection_range,
        extra_principal:  extra_principal_for(transaction),
      )
    end
  end

  def final_month
    (date >> months) - 1
  end

  def monthly_payment
    iv  = initial_value
    r   = rate
    n   = months
    (iv * r) / (1 - ((1 + r) ** (-n)))
  end

  def next_schedule result
    super.tap do |hash|
      hash[:months] = months - result.months_amortized
    end
  end

  def validate! transaction
    unless transaction_balanced? transaction
      raise Projector::BalanceError, "Debits and credits for extra principal payments do not balance"
    end
    %i(interest payment principal).each do |route|
      unless account_map.has_key? route
        raise Projector::InvalidTransaction, "Schedule must supply accounts, missing #{route.inspect}"
      end
    end
    transaction.debits.each do |bit|
      account = bit.fetch :account
      next if bit.fetch(:amount).is_a? Symbol
      unless account == principal_account
        raise Projector::InvalidTransaction, "Extra payments must go to liability or payment account (#{account.inspect} must equal #{payment_account.inspect}"
      end
    end
  end

  def transaction_balanced? transaction
    extra_principal_amount(transaction, :debits) ==
      extra_principal_amount(transaction, :credits)
  end

  def yield_for_each_bit_on_amortizer amortizer
    yield :credit, amortizer.interest,  payment_account
    yield :credit, amortizer.principal, payment_account
    yield :debit,  amortizer.interest,  interest_account
    yield :debit,  amortizer.principal, principal_account
  end

  private

  def extra_principal_for transaction
    extra_principal_amount transaction, :debits
  end

  def extra_principal_for? transaction
    extra_principal_amount(transaction, :debits) != 0 ||
      extra_principal_amount(transaction, :credits) != 0
  end

  def extra_principal_amount transaction, credits_or_debits = :both
    transaction.public_send(credits_or_debits).reduce 0 do |sum, bit|
      amount = bit.fetch :amount
      if amount.is_a? Numeric
        sum + amount
      else
        sum
      end
    end
  end
end
