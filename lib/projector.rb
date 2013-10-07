class Projector
  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1

  AccountExists = Class.new ArgumentError
  BalanceError = Class.new ArgumentError
  InvalidAccount = Class.new ArgumentError
  InvalidTransaction = Class.new ArgumentError

  attr :accounts, :from, :transactions

  class << self
    def with_banker_rounding
      old_rounding_mode = BigDecimal.mode BigDecimal::ROUND_MODE
      BigDecimal.mode BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN
      yield
    ensure
      BigDecimal.mode BigDecimal::ROUND_MODE, old_rounding_mode
    end
  end

  def initialize from: ABSOLUTE_START
    @from = from
    @accounts = {} 
    @transactions = []
  end

  def accounts= accounts_hash
    accounts.clear
    accounts_hash.each { |id, hash| add_account id, hash }
  end

  def account_balance account_id
    accounts.fetch(account_id).balance
  end

  def account_balances type
    accounts.reduce 0 do |sum, (_, account)|
      sum + (account.type == type ? account.balance : 0)
    end
  end

  def add_account account_id, account_or_hash
    account = build_or_dup_object Account, account_or_hash do |hash|
      hash[:name] ||= Account.default_account_name account_id
      Account.new hash
    end
    validate_account! account_id, account
    accounts[account_id] = account
  end

  def add_transaction transaction_or_hash
    transaction = build_or_dup_object Transaction, transaction_or_hash
    validate_transaction! transaction
    transactions.push transaction
  end

  def balance
    accounts.inject 0 do |sum, (_, account)|
      if %i(asset expense).include? account.type
        sum += account.balance
      else
        sum -= account.balance
      end
    end
  end

  def check_balance!
    unless balance == 0
      raise BalanceError, "You cannot run a projection with accounts that "\
        "aren't balanced; balance is #{balance.inspect}"
    end
  end

  def freeze
    @accounts.freeze
    @transactions.freeze
  end

  def project to: nil, &block
    freeze
    check_balance!
    next_projector = self.class.new from: (to + 1)
    next_projector.accounts = accounts
    projector = Projection.new(
      self, 
      range: (from..to),
      next_projector: next_projector
    )
    projector.project! &block
    next_projector
  end

  def transactions= new_transactions
    transactions.clear
    new_transactions.each do |transaction| add_transaction transaction; end
  end

  def split_account parent_id, into: []
    parent = accounts.fetch parent_id
    into.map do |child_id|
      child = Account.new(
        name:      Account.default_account_name(parent_id),
        open_date: parent.open_date,
        parent_id: parent_id,
        type:      parent.type,
      )
      add_account child_id, child
    end
  end

  private

  def build_or_dup_object klass, object_or_hash
    if object_or_hash.is_a? klass
      object_or_hash.dup
    elsif block_given?
      yield object_or_hash
    else
      klass.new object_or_hash
    end
  end

  def validate_account! id, account
    existing_account = accounts[id]
    if existing_account
      raise Projector::AccountExists, "Account `#{id}' exists; name is "\
        "`#{existing_account.name}'"
    end
    unless Account::TYPES.include? account.type
      raise Projector::InvalidAccount, "Account `#{account.name}', does not "\
        "have a type in #{Account::TYPES.join(', ')}"
    end
    if account.balance > 0 && account.open_date > from
      raise Projector::BalanceError, "Projection starts on #{from}, and "\
        "account `#{account.name}' starts on #{account.open_date} with a "\
        "nonzero opening balance of #{account.balance}"
    end
  end

  def validate_transaction! transaction
    if transaction.before? from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{from} vs. #{transaction.date})"
    end
  end

end
