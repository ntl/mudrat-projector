class Schedule
  attr :count, :scalar, :unit

  def initialize params = {}
    @count  = params.fetch :count, nil
    @scalar = params.fetch :scalar
    @unit   = params.fetch :unit
  end

  def finished?
    (count.nil? || count > 0) ? false : true
  end

  def split_count_over range
    diff = DateDiff.date_diff unit: unit, from: range.begin, to: range.end
    full_units, final_prorate = [@count, diff].compact.min.divmod 1
    ([1] * full_units).tap do |list|
      list.push final_prorate unless final_prorate.zero?
    end
  end

  def serialize
    {
      scalar: scalar,
      unit:   unit,
    }.tap { |h| h[:count] = count if count }
  end

  def slice range, &block
    date = range.begin
    split_count_over(range).each do |factor|
      @count -= factor if @count
      yield date, factor if block_given?
      date = DateDiff.advance intervals: factor, unit: unit, from: date
    end
    finished? ? nil : serialize
  end
end
