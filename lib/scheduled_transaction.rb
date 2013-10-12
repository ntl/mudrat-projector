class ScheduledTransaction < Transaction
  attr :schedule

  def initialize params = {}
    @schedule = Schedule.new params.fetch :schedule
    super params
  end

  def slice slice_date
    txns_before_date = []
    next_schedule = schedule.slice(date..slice_date) do |new_date, prorate|
      txns_before_date.push clone_transaction new_date: new_date
    end
    if next_schedule
      leftover = clone_transaction new_date: slice_date + 1, new_schedule: next_schedule
    end
    [txns_before_date, leftover]
  end

  def clone_transaction new_date: date, new_schedule: nil
    params = { debits: debits, credits: credits, date: new_date }
    return Transaction.new(params) if new_schedule.nil?
    params[:schedule] = new_schedule
    ScheduledTransaction.new params
  end
end
