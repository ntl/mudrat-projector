module MudratProjector
  class Schedule
    attr :count, :scalar, :unit

    def initialize params = {}
      @count  = params.fetch :count, nil
      @scalar = params.fetch :scalar
      @unit   = params.fetch :unit
    end

    def advance_over range
      split_count_over(range).reduce range.begin do |date, factor|
        @count -= factor if @count
        yield [date, factor]
        scalar.times.reduce date do |date, _|
          DateDiff.advance intervals: factor, unit: unit, from: date
        end
      end
    end

    def finished?
      (count.nil? || count > 0) ? false : true
    end

    def split_count_over range
      diff = DateDiff.date_diff unit: unit, from: range.begin, to: range.end
      full_units, final_prorate = [@count, diff].compact.min.divmod scalar
      final_prorate /= scalar
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
      bits = []
      advance_over range do |date, factor| bits.push [date, factor]; end
      leftover = finished? ? nil : serialize
      [bits, leftover]
    end
  end
end
