require_relative 'date_diff'
require_relative 'tax_calculator'

class Projector
  attr_accessor :accounts, :transactions, :tax_info

  def initialize
    @transactions = []
  end

  def project! from: nil, to: nil
    initial = get_initial
    total = initial
    taxes_paid = calculate_taxes_paid from, to

    transactions.each do |transaction|
      amount = transaction.fetch :amount
      number, interval = transaction.fetch :recurring_schedule
      date = [transaction.fetch(:date, from), from].max
      end_date = transaction.fetch :end_date, to
      next if date > to || end_date < from
      time = DateDiff.date_diff unit: interval, from: date, to: end_date
      total += (amount / number.to_f) * time
    end

    OpenStruct.new(
      gross_revenue: total - initial,
      net_revenue: total - taxes_paid - initial,
      net_worth: total - taxes_paid,
    )
  end

  def calculate_taxes_paid from, to
    (from.year..to.year).inject 0 do |sum, year|
      is = income_sources year
      if is.empty?
        sum
      else
        tax_calculator = TaxCalculator.new(
          household: OpenStruct.new(tax_info.fetch(year)),
          year: year,
          income_sources: is,
          expenses: {},
        )
        sum + tax_calculator.taxes_paid
      end
    end
  end

  def income_sources year
    transactions.each_with_object [] do |transaction, ary|
      if Array(transaction[:tags]).include? :income
        annual = to_annual transaction, year
        ary.push(
          annual_gross: annual,
          tax_form: tax_form(transaction),
          pay_interval: [1, :year],
          paycheck_gross: annual,
        )
      end
    end
  end

  def to_annual transaction, year
    base = transaction.fetch :amount
    number, interval = transaction.fetch :recurring_schedule
    factor = {
      year: 1.0,
      quarter: 4.0,
      month: 12.0,
      week: 52.0,
      day: Date.new(year).leap? ? 366.0 : 365.0,
    }.fetch interval
    (base * factor) / number.to_f
  end

  def tax_form transaction
    if Array(transaction[:tags]).include? :w2
      'w2'
    elsif Array(transaction[:tags]).include? '1099'.to_sym
      '1099'
    end
  end

  def get_initial
    accounts.inject 0 do |sum, account|
      sum += account.fetch :initial_balance, 0
    end
  end
end
