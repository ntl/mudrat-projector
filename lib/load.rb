load File.expand_path('../date_diff.rb', __FILE__)

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
      time = DateDiff.date_diff unit: interval, from: date, to: end_date
      total += (amount / number.to_f) * time
    end

    OpenStruct.new(
      gross_revenue: total - initial,
      net_revenue: total - initial,
      net_worth: total,
    )
  end
end
