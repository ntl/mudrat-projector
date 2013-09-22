class Transaction
  attr :credits, :date, :debits, :recurring_schedule

  RecurringSchedule = Struct.new :number, :unit, :end do
    def initialize *args
      super
      freeze
    end
  end

  def initialize params = {}
    @date = params.fetch :date, Projector::ABSOLUTE_START
    @credits = Array params[:credits]
    @debits  = Array params[:debits]
    @credits << params[:credit] if params[:credit]
    @debits  << params[:debit]  if params[:debit]
    if params[:recurring_schedule]
      @recurring_schedule = build_recurring_schedule *params[:recurring_schedule]
    end
    freeze
  end

  def after? date
    date > date
  end

  def closes_in_range? range
    if recurring_schedule
      recurring_schedule.end < range.end
    else
      date < range.end
    end
  end

  def apply! projector, &block
    validate! projector
    range = projector.range
    if date > range.end
      return self
    elsif recurring_schedule
      txn_start = [range.begin, date].max
      txn_end   = [range.end, recurring_schedule.end].min
      range_multiplier = [
        DateDiff.date_diff(
          unit: recurring_schedule.unit,
          from: txn_start,
          to:   txn_end,
        ),
        (1.0 / recurring_schedule.number),
      ].inject &:*
      each_bit range_multiplier, &block
      if recurring_schedule.end <= range.end
        nil
      else
        new_start = range.end + 1
        new_recurring_schedule = [
          recurring_schedule.number,
          recurring_schedule.unit,
          recurring_schedule.end,
        ]
        self.class.new(
          date:    new_start,
          credits: credits,
          debits:  debits,
          recurring_schedule: new_recurring_schedule,
        )
      end
    else
      each_bit &block
      nil
    end
  end

  def validate! projector
    if projector.from > date
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{projector.from} vs. #{date})"
    end
    total_credits, total_debits = total_credits_and_debits
    unless total_credits == total_debits
      raise Projector::BalanceError, "Debits and credits do not balance"
    end
  end

  private

  def build_recurring_schedule number, unit, to = Projector::ABSOLUTE_END
    RecurringSchedule.new number, unit, to
  end

  def each_bit multiplier = 1
    credits.each do |amount, account_id|
      yield :credit, amount * multiplier, account_id
    end
    debits.each do |amount, account_id|
      yield :debit, amount * multiplier, account_id
    end
  end

  def total_credits_and_debits
    credit_amounts = credits.map &:first
    debit_amounts  = debits.map  &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    [sum_of.call(credit_amounts), sum_of.call(debit_amounts)]
  end
end
