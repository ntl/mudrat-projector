module DateDiff
  extend self

  def date_diff type, from, to
    send "diff_#{type}s", from, to
  end

  def diff_years from, to
    if to.year == from.year
      days_in_year = from.leap? ? 366.0 : 365.0
      ((to + 1) - from).to_f / days_in_year
    else
      first_year = diff_years from, Date.new(from.year, 12, 31)
      last_year  = diff_years Date.new(to.year, 1, 1), to
      years_between = (to.year - 1) - from.year
      first_year + years_between + last_year
    end
  end

  def diff_quarters from, to
    from_quarter = fetch_quarter from
    to_quarter   = fetch_quarter to
    if from_quarter == to_quarter
      diff_days(from, to) / days_in_quarter(from_quarter)
    else
      end_of_first_quarter = from_quarter.next_month.next_month.next_month - 1
      first_quarter = diff_quarters from, end_of_first_quarter
      last_quarter = diff_quarters to_quarter, to
      quarters_between = quarters_between end_of_first_quarter + 1, to_quarter.prev_month.prev_month.prev_month
      first_quarter + quarters_between + last_quarter
    end
  end

  def diff_months from, to
    if to.month == from.month
      ((to + 1) - from).to_f / days_in_month(from)
    else
      end_of_first_month = Date.new(from.next_month.year, from.next_month.month, 1) - 1
      first_month = diff_months from, end_of_first_month
      start_of_last_month = Date.new to.year, to.month, 1
      last_month = diff_months start_of_last_month, to
      months_between = months_between end_of_first_month + 1, start_of_last_month.prev_month
      first_month + months_between + last_month
    end
  end

  def diff_weeks from, to
    diff_days(from, to) / 7.0
  end

  def diff_days from, to
    (to - from).to_f + 1
  end

  private

  def fetch_quarter date
    [1, 4, 7, 10].each do |quarter|
      if (quarter..quarter + 2).include? date.month
        return Date.new(date.year, quarter)
      end
    end
    fail "Date month was #{date.month}"
  end

  def days_in_quarter start_of_quarter
    days_in_month(start_of_quarter) + 
    days_in_month(start_of_quarter.next_month) +
    days_in_month(start_of_quarter.next_month.next_month)
  end

  def days_in_month date
    start_of_month = Date.new date.year, date.month, 1
    end_of_month = start_of_month.next_month
    (end_of_month - start_of_month).to_f
  end

  def quarters_between start, finish
    return 0 if start > finish
    pos = start
    count = 1
    until pos == finish
      count += 1
      pos = pos.next_month.next_month.next_month
    end
    count
  end

  def months_between start, finish
    return 0 if start > finish
    pos = start
    count = 1
    until pos == finish
      count += 1
      pos = pos.next_month
    end
    count
  end
end

class Projector
  attr_accessor :accounts, :transactions

  def initialize
    @transactions = []
  end

  def project! from: nil, to: nil
    initial = 0
    total = initial

    transactions.each do |transaction|
      amount = transaction.fetch :amount
      number, interval = transaction.fetch :recurring_schedule
      date = transaction.fetch :date, from
      end_date = transaction.fetch :end_date, to
      next if date > to || end_date < from
      time = DateDiff.date_diff interval, date, end_date
      total += (amount / number.to_f) * time
    end

    OpenStruct.new(
      gross_revenue: total - initial,
      net_revenue: total - initial,
      net_worth: total,
    )
  end
end
