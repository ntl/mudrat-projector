module DateDiff
  extend self

  def advance intervals: nil, unit: nil, from: nil
    fetch_subclass(unit).advance intervals, from: from
  end

  def date_diff *maybe_unit_from_to, unit: nil, from: nil, to: nil
    if [unit, from, to].all? &:nil?
      unit, from, to = maybe_unit_from_to
    end
    fetch_subclass(unit).new(from, to).calculate
  end

  def fetch_subclass unit
    klass_bit = unit.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter| 
      dash_letter[1].upcase
    end
    klass_name = "#{klass_bit}Calculator"
    DateDiff.const_get klass_name
  end
  private :fetch_subclass

  Calculator = Struct.new :from, :to do
    def calculate
      fail
    end

    def days_between
      (to - from).to_f + 1
    end
    private :days_between
  end

  class DayCalculator < Calculator
    def calculate
      days_between
    end
    
    def self.advance intervals, from: from
      from + intervals.round
    end
  end

  class WeekCalculator < DayCalculator
    def calculate
      super / 7.0
    end

    def self.advance intervals, from: from
      from + (intervals * 7)
    end
  end

  class ComplexCalculator < Calculator
    attr :first_unit, :last_unit

    def initialize *args
      super
      @first_unit = fetch_unit from
      @last_unit  = fetch_unit to
    end

    def calculate
      if first_unit.begin == last_unit.begin
        days_between / days_in_unit(first_unit)
      else
        calculate_unit(from, first_unit.end) +
          units_between +
          calculate_unit(last_unit.begin, to)
      end
    end

    private

    def calculate_unit unit_begin, unit_end
      self.class.new(unit_begin, unit_end).calculate
    end

    def calculate_units_between start, finish
      count = 1
      until start == finish
        count += 1
        start = advance_one_unit start
      end
      count
    end

    def days_in_unit unit
      ((unit.end + 1) - unit.begin).to_f
    end

    def units_between
      start = first_unit.end + 1
      finish = rewind_one_unit last_unit.begin
      return 0 if start > finish
      calculate_units_between start, finish
    end
  end

  class YearCalculator < ComplexCalculator
    def fetch_unit date
      (Date.new(date.year)..Date.new(date.year, 12, 31))
    end

    def advance_one_unit date
      date.next_year
    end

    def rewind_one_unit date
      date.prev_year
    end

    def self.advance intervals, from: from
      Date.new(from.year + intervals, from.month, from.day)
    end
  end

  class QuarterCalculator < ComplexCalculator
    def fetch_unit date
      [1, 4, 7, 10].each do |quarter|
        if (quarter..quarter + 2).include? date.month
          start_of_quarter = Date.new(date.year, quarter)
          return (start_of_quarter..(start_of_quarter.next_month.next_month.next_month - 1))
        end
      end
      fail "Date month was #{date.month}"
    end

    def advance_one_unit date
      date.next_month.next_month.next_month
    end

    def rewind_one_unit date
      date.prev_month.prev_month.prev_month
    end

    def self.advance intervals, from: from
      (intervals * 3).times.inject from do |date, _| date.next_month; end
    end
  end

  class MonthCalculator < ComplexCalculator
    def fetch_unit date
      start_of_month = Date.new(date.year, date.month)
      (start_of_month..(start_of_month.next_month - 1))
    end

    def advance_one_unit date
      date.next_month
    end

    def rewind_one_unit date
      date.prev_month
    end

    def self.advance intervals, from: from
      if intervals < 1
        days_in_month = Date.new(from.year, from.month, -1).day
        days = intervals * days_in_month
        DayCalculator.advance days, from: from
      else
        intervals.times.inject from do |date, _| date.next_month; end
      end
    end
  end

end
