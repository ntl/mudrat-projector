class ScheduledTransaction < Transaction
  attr :schedule

  def initialize params = {}
    @schedule = Schedule.new params.fetch :schedule
    super params
  end

  def build_transactions intervals
    intervals.map do |date, prorate|
      clone_transaction new_date: date, multiplier: prorate
    end
  end

  def clone_transaction new_date: date, new_schedule: nil, multiplier: 1
    params = build_cloned_tranasction_params new_date, multiplier
    return Transaction.new(params) if new_schedule.nil?
    params[:schedule] = new_schedule
    ScheduledTransaction.new params
  end

  def multiply entries, by: 1
    entries.map do |entry| entry * by; end
  end

  def slice slice_date
    intervals, next_schedule = schedule.slice(date..slice_date)
    if next_schedule
      leftover = clone_transaction new_date: slice_date + 1, new_schedule: next_schedule
    end
    [build_transactions(intervals), leftover]
  end

  private

  def build_cloned_tranasction_params new_date, multiplier
    {
      date: new_date,
      debits: multiply(debits, by: multiplier), 
      credits: multiply(credits, by: multiplier),
    }
  end
end
