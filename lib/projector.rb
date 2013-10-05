class Projector
  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1

  AccountExists = Class.new ArgumentError
  BalanceError = Class.new ArgumentError
  InvalidAccount = Class.new ArgumentError
  InvalidTransaction = Class.new ArgumentError

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

    def with_banker_rounding
      old_rounding_mode = BigDecimal.mode BigDecimal::ROUND_MODE
      BigDecimal.mode BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN
      yield
    ensure
      BigDecimal.mode BigDecimal::ROUND_MODE, old_rounding_mode
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

  def add_account id, account_or_hash
    if account_or_hash.is_a? Account
      account = account_or_hash
    else
      account = Account.new id, account_or_hash
    end
    account.validate! self
    accounts[id] = account
  end

  def add_transaction transaction_or_hash
    if transaction_or_hash.is_a? Transaction
      transaction = transaction_or_hash
    else
      transaction = Transaction.new transaction_or_hash
    end
    transaction.validate! self
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

  def project to: nil, &block
    freeze
    must_be_balanced!
    Projection.new(self, from: from, to: to, transaction_callback: block).tap &:project
  end

  def split_account parent_id, into: []
    accounts.fetch(parent_id).split(into: into).each do |child|
      add_account child.id, child
    end
  end

  private

  def must_be_balanced!
    unless balanced?
      raise BalanceError, "You cannot run a projection with accounts that "\
        "aren't balanced; balance is #{opening_balance.inspect}"
    end
  end

end
