class Schedule
  attr :date

  def initialize date
    @date = date
  end
end

class RecurringSchedule < Schedule
  attr :number, :schedule_end, :unit

  def initialize date, params = {}
    @number        = params.fetch :number
    @schedule_end  = params[:end] || Projector::ABSOLUTE_END
    @unit          = params.fetch :unit
    super date
  end

  def advance scheduled_transaction, over: nil
    multiplier = calculate_multiplier_factor over
    transaction = Transaction.new(
      credits: multiply(scheduled_transaction.credits, by: multiplier),
      debits:  multiply(scheduled_transaction.debits,  by: multiplier),
      date:    over.end,
    )
    if schedule_end > over.end
      next_transaction = ScheduledTransaction.new(
        date:     (over.end + 1),
        credits:  scheduled_transaction.credits,
        debits:   scheduled_transaction.debits,
        schedule: self,
      )
      [transaction, next_transaction]
    else
      transaction
    end
  end

  def calculate_multiplier_factor projection_range
    range_begin = projection_range.begin
    range_end   = [projection_range.end, schedule_end].min
    factor = DateDiff.date_diff unit: unit, from: range_begin, to: range_end
    factor / number
  end

  def multiply entries, by: nil
    entries.map do |entry|
      TransactionEntry.new(
        entry.credit_debit,
        entry.amount * by,
        entry.account_id,
      )
    end
  end
end

__END__
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

  def reduce transaction, range
    return transaction if after? range.end
    reducer = build_reducer transaction, range
    reduced_transaction = reduce_transaction transaction, range, reducer
    next_transaction = __build_next_transaction transaction, range, reducer
    [next_transaction, reduced_transaction].compact
  end

  def reduce_transaction transaction, range, reducer
    entries = {
      credit: Hash.new { |h,k| h[k] = 0 },
      debit:  Hash.new { |h,k| h[k] = 0 },
    }

    reducer.each_entry do |credit_or_debit, amount, account_id|
      entries.fetch(credit_or_debit)[account_id] += amount
    end

    Transaction.new(
      date: range.end,
      credits: entries.fetch(:credit).to_a.map(&:reverse),
      debits: entries.fetch(:debit).to_a.map(&:reverse),
    )
  end

  def transaction_balanced? transaction
    credit_amounts = transaction.credits.map &:first
    debit_amounts  = transaction.debits.map  &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    sum_of.(credit_amounts) == sum_of.(debit_amounts)
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

  private

  def __build_next_transaction transaction, range, reducer
    if method(:build_next_transaction).arity == 3
      build_next_transaction transaction, range, reducer
    else
      build_next_transaction transaction, range
    end
  end

end

class OneTimeSchedule < Schedule
  def apply! transaction, range, &block
    yield_over_each_bit transaction.credits, transaction.debits, &block
  end

  def reduce transaction, projection
    transaction
  end
end

class RecurringSchedule < Schedule
  attr :end, :number, :unit

  Multiplier = Struct.new :transaction, :factor do
    def each_entry
      transaction.each_entry do |credit_or_debit, amount, account_id|
        yield credit_or_debit, amount * factor, account_id
      end
    end
  end

  def initialize date, params = {}
    @end    = params[:end] || Projector::ABSOLUTE_END
    @number = params.fetch :number
    @unit   = params.fetch :unit
    super date
  end

  def build_multiplier transaction, range
    Multiplier.new transaction, calculate_multiplier_factor(range)
  end
  alias_method :build_reducer, :build_multiplier

  def build_next_transaction transaction, range
    Transaction.new(
      date:     range.end + 1,
      credits:  transaction.credits,
      debits:   transaction.debits,
      schedule: to_hash,
    )
  end

  def to_hash
    {
      end:    self.end,
      number: number,
      type:   :recurring,
      unit:   unit,
    }
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

  def build_amortizer transaction, range
    Projector.with_banker_rounding do
      CompoundInterestAmortizer.new self, range
    end
  end
  alias_method :build_reducer, :build_amortizer

  def build_next_transaction transaction, range, amortizer
    amortizer.next_transaction(
      transaction,
      next_schedule(amortizer),
    )
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
end

class MortgageSchedule < CompoundSchedule
  attr :months

  def initialize date, params = {}
    @months = params.fetch :months
    super date, params
  end

  def build_reducer transaction, range
    Projector.with_banker_rounding do
      extra_principal = extra_principal_for transaction
      MortgageAmortizer.new self, range, extra_principal: extra_principal
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
