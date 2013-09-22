class Projector
  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1
  ACCOUNT_TYPES = %i(asset expense liability revenue)

  AccountExists = Class.new ArgumentError
  BalanceError = Class.new ArgumentError
  InvalidAccount = Class.new ArgumentError

  attr :accounts, :transactions

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
    Projection.new(
      self,
      from:                from,
      to:                  to,
    ).tap &:project
  end

  def split_account parent_id, into: []
    into.map do |child_account_id|
      add_account child_account_id, build_child_account_hash(parent_id)
    end
  end

  private

  def build_account_from_hash id, hash
    hash = {
      name: default_account_name(id),
      open_date: ABSOLUTE_START,
    }.merge hash
    OpenStruct.new hash
  end

  def build_child_account_hash parent_id
    parent = accounts.fetch parent_id
    {
      open_date: parent.open_date,
      parent_id: parent_id,
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
    if recurring_schedule = default[:recurring_schedule]
      default[:recurring_schedule] = OpenStruct.new(
        number: recurring_schedule.fetch(0),
        unit:   recurring_schedule.fetch(1),
        end:    recurring_schedule.fetch(2, ABSOLUTE_END),
      )
    end
    OpenStruct.new(default).tap do |t|
      def t.each_bit
        credits.each do |amount, account_id|
          yield :credit, amount, account_id
        end
        debits.each do |amount, account_id|
          yield :debit, amount, account_id
        end
      end
    end
  end

  def default_account_name id
    id.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter|
      dash_letter[1].upcase
    end
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
