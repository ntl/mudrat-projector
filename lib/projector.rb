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
  end

  def_delegators :@chart, *%i(accounts account_balance balance fetch net_worth split_account)

  def accounts= accounts
    accounts.each do |account_id, params|
      add_account account_id, params
    end
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

  private

  def must_be_balanced!
    unless balanced?
      raise Projector::BalanceError, "Cannot project unless the accounts "\
        "are in balance"
    end
  end

  def validate_account! account_id, params
    if @chart.exists? account_id
      raise Projector::AccountExists, "Account #{account_id.inspect} exists"
    end
    unless Account::TYPES.include? params[:type]
      raise Projector::InvalidAccount, "Account #{account_id.inspect} has "\
        "invalid type #{params[:type].inspect}"
    end
    if params.has_key?(:open_date) && params[:open_date] > from
      if params.has_key? :opening_balance
        raise Projector::InvalidAccount, "Account #{account_id.inspect} opens "\
          "after projector, but has an opening balance"
      end
    end
  end

  def validate_transaction! transaction
    if transaction.date < from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{from} vs. #{transaction.date})"
    end
    unless transaction.balanced?
      raise Projector::BalanceError, "Credits and debit entries both "\
        "must be supplied; they cannot amount to zero"
    end
    if transaction.credits.empty? || transaction.debits.empty?
      raise Projector::InvalidTransaction, "You must supply at least a debit "\
        "and a credit on each transaction"
    end
  end

end
