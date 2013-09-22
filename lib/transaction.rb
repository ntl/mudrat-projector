class Transaction
  attr :credits, :date, :debits, :recurring_schedule

  RecurringSchedule = Struct.new :number, :unit, :from, :to do
    def range
      (from..to)
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

  def active_in_range? range
    if recurring_schedule
      schedule_range = recurring_schedule.range
      if schedule_range.begin < range.begin && schedule_range.end > range.end
        true
      else
        range.include?(schedule_range.begin) ||
          range.include?(schedule_range.end)
      end
    else
      range.include? date
    end
  end

  def closes_in_range? range
    if recurring_schedule
      recurring_schedule.to < range.end
    else
      date < range.end
    end
  end

  def each_bit
    credits.each do |amount, account_id|
      yield :credit, amount, account_id
    end
    debits.each do |amount, account_id|
      yield :debit, amount, account_id
    end
  end

  def validate!
    total_credits, total_debits = total_credits_and_debits
    unless total_credits == total_debits
      raise Projector::BalanceError, "Debits and credits do not balance"
    end
  end

  private

  def build_recurring_schedule number, unit, to = Projector::ABSOLUTE_END
    RecurringSchedule.new number, unit, date, to
  end

  def total_credits_and_debits
    credit_amounts = credits.map &:first
    debit_amounts  = debits.map  &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    [sum_of.call(credit_amounts), sum_of.call(debit_amounts)]
  end
end
