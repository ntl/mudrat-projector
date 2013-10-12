class ScheduledTransaction < Transaction
  attr :schedule

  def initialize params = {}
    @schedule = build_schedule params.fetch :schedule
    super params
  end

  def slice slice_date
    txns_before_date = []
    next_schedule = schedule.each_occurrence(date..slice_date) do |date, prorate|
      txns_before_date << Transaction.new(
        date: date,
        debits: debits,
        credits: credits,
      )
    end
    if next_schedule
      leftover = ScheduledTransaction.new(
        date: slice_date + 1,
        debits: debits,
        credits: credits,
        schedule: next_schedule,
      )
    else
      leftover = nil
    end
    [txns_before_date, leftover]
  end

  def build_schedule schedule_params
    Schedule.new schedule_params
  end
end
