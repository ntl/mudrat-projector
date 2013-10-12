class Schedule
  attr :count, :scalar, :unit

  def initialize params = {}
    @count  = params.fetch :count, nil
    @scalar = params.fetch :scalar
    @unit   = params.fetch :unit
  end

  def advance range, &block
    diff = DateDiff.date_diff unit: unit, from: range.begin, to: range.end
    units, final_prorate = [@count, diff].compact.min.divmod 1
    final_date = units.times.inject range.begin do |date, _|
      @count -=1 if @count
      yield date, 1 if block_given?
      DateDiff.advance intervals: 1, unit: unit, from: date
    end
    unless final_prorate.zero?
      @count -= 1 if @count
      yield final_date, final_prorate if block_given?
    end
    if count.nil? || count > 0
      serialize
    else
      nil
    end
  end
  alias_method :each_occurrence, :advance

  def serialize
    {
      scalar: scalar,
      unit:   unit,
    }.tap { |h| h[:count] = count if count }
  end
end

__END__
  attr :date, :number, :schedule_end, :unit

  def initialize date, params = {}
    @date          = date
    @number        = params.fetch :number
    @schedule_end  = params[:end] || Projector::ABSOLUTE_END
    @unit          = params.fetch :unit
  end

  def advance scheduled_transaction, over: nil, &block
    extract_transactions scheduled_transaction, over, &block
    if schedule_end > over.end
      build_transaction scheduled_transaction, date: over.end + 1, schedule: self
    end
  end

  def build_transaction source_transaction, multiplier: 1, date: nil, schedule: nil
    Transaction.new(
      credits: multiply(source_transaction.credits, by: multiplier),
      debits:  multiply(source_transaction.debits,  by: multiplier),
      date:    date,
      schedule: schedule,
    )
  end

  def calculate_multiplier_factor projection_range
    range_begin = projection_range.begin
    range_end   = [projection_range.end, schedule_end].min
    factor = DateDiff.date_diff unit: unit, from: range_begin, to: range_end
    factor / number
  end

  def extract_transactions source_transaction, range
    full, prorated = calculate_multiplier_factor(range).divmod 1
    full.times do |step|
      date = DateDiff.advance intervals: step, unit: unit, from: range.begin
      yield build_transaction(source_transaction, date: date)
    end
    unless prorated.zero?
      yield build_transaction(source_transaction, multiplier: prorated, date: range.end)
    end
  end

  def multiply entries, by: nil
    return entries if by == 1
    entries.map do |entry|
      multiply_transaction_entry entry, by: by
    end
  end

  def multiply_transaction_entry entry, by: nil
    TransactionEntry.new(
      entry.credit_debit,
      entry.amount * by,
      entry.account_id,
    )
  end
end
