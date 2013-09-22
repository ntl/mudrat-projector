class Projector
  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1
  ACCOUNT_TYPES = %i(asset expense liability revenue equity)

  AccountExists = Class.new ArgumentError
  BalanceError = Class.new ArgumentError
  InvalidAccount = Class.new ArgumentError

  attr :accounts, :from, :transactions

  def initialize from: ABSOLUTE_START
    @from = from
    @accounts = {} 
    @transactions = []
  end

  class << self
    def new(existing_projection = nil, **params)
      if existing_projection
        import_projection projection: existing_projection
      else
        super params
      end
    end

    private

    def import_projection projection: projection
      new(from: projection.to + 1).tap do |projector|
        projector.accounts     = projection.accounts
        projector.transactions = projection.transactions
      end
    end
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

  def add_transaction transaction_or_hash
    if transaction_or_hash.is_a? Transaction
      transaction = transaction_or_hash
    else
      transaction = Transaction.new transaction_or_hash
    end
    transaction.validate!
    transactions.push transaction
  end

  def balanced?
    opening_balance == 0
  end

  def freeze
    @accounts.freeze
    @transactions.freeze
  end

  def transactions= transactions
    @transactions.clear
    transactions.each do |transaction|
      add_transaction transaction
    end
  end

  def opening_balance
    accounts.inject 0 do |balance, (_, account)|
      if %i(asset expense).include? account.type
        balance += account.opening_balance
      else
        balance -= account.opening_balance
      end
    end
  end

  def project to: nil
    freeze
    Projection.new self, from: from, to: to
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
      open_date: from,
      opening_balance: 0,
    }.merge hash
    if hash.fetch(:opening_balance) > 0 && hash.fetch(:open_date) > from
      raise BalanceError, "Projection starts on #{from}, and account "\
        "#{id.inspect} starts on #{hash[:open_date]} with a nonzero opening "\
        "balance of #{hash[:opening_balance]}"
    end
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

  def default_account_name id
    id.to_s.capitalize.gsub(/_[a-z]/) do |dash_letter|
      dash_letter[1].upcase
    end
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
end
