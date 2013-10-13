class Projector
  extend Forwardable
  extend BankerRounding

  ABSOLUTE_START = Date.new 1970, 1, 1
  ABSOLUTE_END   = Date.new 9999, 1, 1

  AccountDoesNotExist = Class.new StandardError
  AccountExists       = Class.new ArgumentError
  BalanceError        = Class.new StandardError
  InvalidAccount      = Class.new ArgumentError
  InvalidTransaction  = Class.new StandardError

  attr :from

  def initialize params = {}
    @chart        = params.fetch :chart, ChartOfAccounts.new
    @from         = params.fetch :from, ABSOLUTE_START
    @transactions = []
    @validator    = Validator.new projector: self, chart: @chart
  end

  def_delegators :@chart, *%i(accounts account_balance apply_transaction balance fetch net_worth split_account)
  def_delegators :@validator, *%i(must_be_balanced! validate_account! validate_transaction!)

  def accounts= accounts
    accounts.each do |account_id, params|
      add_account account_id, params
    end
  end

  def account_exists? account_id
    @chart.exists? account_id
  end

  def add_account account_id, **params
    validate_account! account_id, params
    @chart.add_account account_id, params
  end

  def add_transaction params
    if params.is_a? Transaction
      transaction = params
    else
      klass = params.has_key?(:schedule) ? ScheduledTransaction : Transaction
      transaction = klass.new params
      validate_transaction! transaction
    end
    @transactions.push transaction
  end

  def balanced?
    balance.zero?
  end

  def project to: end_of_projection, build_next: false, &block
    must_be_balanced!
    projection = Projection.new range: (from..to), chart: @chart
    handler = TransactionHandler.new projection: projection
    if build_next
      handler.next_projector = self.class.new from: to + 1, chart: @chart
    end
    @transactions.each do |transaction| handler << transaction; end
    projection.project! &block
    handler.next_projector
  end

  def transactions= transactions
    transactions.each do |transaction| add_transaction transaction; end
  end

end
