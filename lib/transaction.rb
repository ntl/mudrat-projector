class Transaction
  attr :credits, :debits, :schedule

  class OneTimeSchedule
    attr :date

    def initialize date
      @date = date
      freeze
    end

    def after? other_date
      date > other_date
    end

    def apply! transaction, range, &block
      yield_over_each_bit transaction.credits, transaction.debits, &block
      nil
    end

    def before? other_date
      date < other_date
    end

    def recurring?
      false
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
  end

  class RecurringSchedule < OneTimeSchedule
    attr :end, :number, :unit
      
    def initialize date, number, unit, _end
      @end    = _end
      @number = number
      @unit   = unit
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
        date:    range.end + 1,
        credits: transaction.credits,
        debits:  transaction.debits,
        recurring_schedule: [number, unit, self.end],
      )
    end
  end

  def initialize params = {}
    date = params.fetch :date
    @credits = Array params[:credits]
    @debits  = Array params[:debits]
    @credits << params[:credit] if params[:credit]
    @debits  << params[:debit]  if params[:debit]
    if params[:recurring_schedule]
      @schedule = build_recurring_schedule date, *params[:recurring_schedule]
    else
      @schedule = OneTimeSchedule.new date
    end
    freeze
  end

  def apply! projector, &block
    validate! projector
    if schedule.after? projector.range.end
      self
    else
      schedule.apply! self, projector.range, &block
    end
  end

  def recurring_schedule
    schedule
  end

  def validate! projector
    if schedule.before? projector.from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{projector.from} vs. #{schedule.date})"
    end
    total_credits, total_debits = total_credits_and_debits
    unless total_credits == total_debits
      raise Projector::BalanceError, "Debits and credits do not balance"
    end
  end

  private

  def build_recurring_schedule date, number, unit, to = Projector::ABSOLUTE_END
    RecurringSchedule.new date, number, unit, to
  end

  def total_credits_and_debits
    credit_amounts = credits.map &:first
    debit_amounts  = debits.map  &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    [sum_of.call(credit_amounts), sum_of.call(debit_amounts)]
  end
end
