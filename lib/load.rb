require_relative 'date_diff'
require_relative 'tax_calculator'

class Projector
  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1
  ACCOUNT_TYPES = %i(asset expense liability revenue)

  AccountExists = Class.new ArgumentError
  BalanceError = Class.new ArgumentError
  InvalidAccount = Class.new ArgumentError

  attr :accounts, :range, :transactions

  def initialize
    @accounts = {} 
    @transactions = []
  end

  def accounts= accounts_hash
    accounts.clear
    accounts_hash.each { |id, hash| add_account id, hash }
  end

  def add_account id, hash
    account = build_account_from_hash id, hash
    validate_account! id, account
    accounts[id] = account
  end

  def add_transaction hash
    transaction = build_transaction_from_hash hash
    validate_transaction! transaction
    transactions.push transaction
  end

  def transactions= transactions
    transactions.each do |transaction_hash|
      add_transaction transaction_hash
    end
  end

  def project from: ABSOLUTE_START, to: nil
    @range = (from..to)
    accounts.each { |_, account| account.balance = account.opening_balance }
    OpenStruct.new(
      opening_equity: opening_equity,
      closing_equity: run_projection,
    )
  end

  def split_account parent_account_id, splits = {}
    parent_account = accounts.fetch parent_account_id
    unless splits.values.reduce(&:+) == parent_account.opening_balance
      split_account_balance_error parent_account, splits
    end
    splits.map do |id, opening_balance|
      add_account id, build_child_account_hash(opening_balance, parent_account)
    end
  end

  private

  def apply_credit amount, to: nil
    if %i(asset expense).include? to.type
      apply_transaction_bit :-, amount, to
    else
      apply_transaction_bit :+, amount, to
    end
  end

  def apply_debit amount, to: nil
    if %i(asset expense).include? to.type
      apply_transaction_bit :+, amount, to
    else
      apply_transaction_bit :-, amount, to
    end
  end

  def apply_transaction_bit method, amount, account
    while account
      account.balance = account.balance.send method, amount
      account = account.parent
    end
  end

  def asset_balances
    asset_accounts = accounts.values.select { |account| account.type == :asset }
    asset_accounts.map(&:balance).inject(0) { |sum, balance| sum + balance.to_i }
  end

  def build_account_from_hash id, hash
    hash = {
      name: default_account_name(id),
      open_date: ABSOLUTE_START,
      opening_balance: 0,
    }.merge hash
    OpenStruct.new hash
  end

  def build_child_account_hash opening_balance, parent
    {
      opening_balance: opening_balance,
      open_date: parent.open_date,
      parent: parent,
      type: parent.type,
    }
  end

  def build_transaction_from_hash hash
    default = {
      date: ABSOLUTE_START,
      tags: [],
    }
    default.merge! hash
    if credit = default.delete(:credit)
      default[:credits] = [credit]
    end
    if debit = default.delete(:debit)
      default[:debits] = [debit]
    end
    recurring_schedule = default[:recurring_schedule]
    if recurring_schedule
      default[:recurring_schedule] = OpenStruct.new(
        number: recurring_schedule.fetch(0),
        unit:   recurring_schedule.fetch(1),
        end:    recurring_schedule.fetch(2, ABSOLUTE_END),
      )
    end
    OpenStruct.new default
  end

  def run_projection
    transactions.each do |transaction|
      transaction.credits.each do |amount, account_id|
        account = accounts.fetch account_id
        total_amount = get_total_amount amount, transaction, account
        apply_credit total_amount, to: account
      end
      transaction.debits.each do |amount, account_id|
        account = accounts.fetch account_id
        total_amount = get_total_amount amount, transaction, account
        apply_debit total_amount, to: account
      end
    end
    asset_balances
  end

  def default_account_name id
    id.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter|
      dash_letter[1].upcase
    end
  end

  def get_total_amount amount, transaction, account
    recurring_schedule = transaction.recurring_schedule
    if recurring_schedule
      txn_start = [range.begin, transaction.date].max
      txn_end   = [range.end, recurring_schedule.end].min
      [
        amount,
        DateDiff.date_diff(
          unit: recurring_schedule.unit,
          from: txn_start,
          to:   txn_end,
        ),
        (1.0 / recurring_schedule.number),
      ].inject { |a,v| a * v }
    else
      amount
    end
  end

  def opening_equity
    accounts.inject 0 do |sum, (id, account)|
      if account.open_date <= range.begin
        sum + account.opening_balance
      else
        sum
      end
    end
  end

  def split_account_balance_error parent_account, splits
    fmt_accounts = splits.each_with_object [] do |(id, opening_balance), ary|
      ary.push "#{id.inspect} (#{opening_balance})"
    end.join ', '
    raise BalanceError, "Accounts #{fmt_accounts} do not add up to account "\
      "#{parent_account.name.inspect} opening balance of "\
      "#{parent_account.opening_balance}"
  end

  def total_credits_and_debits_for transaction
    credits = transaction.credits.map &:first
    debits  = transaction.debits.map &:first
    sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
    [sum_of.call(credits), sum_of.call(debits)]
  end

  def validate_account! id, account
    existing_account = accounts[id]
    if existing_account
      raise AccountExists, "Account `#{id}' exists; name is `#{existing_account.name}'"
    end
    unless ACCOUNT_TYPES.include? account.type
      raise InvalidAccount, "Account `#{id}', named `#{account.name}', does not have a type in #{ACCOUNT_TYPES.join(', ')}"
    end
  end

  def validate_transaction! transaction
    credits, debits = total_credits_and_debits_for transaction
    unless credits == debits
      raise BalanceError, "Debits and credits do not balance"
    end
  end
end

__END__

  public

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
