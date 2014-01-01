module MudratProjector
  class Projector
    extend Forwardable
    extend BankerRounding

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
      @transaction_with_ids = {}
      @validator    = Validator.new projector: self, chart: @chart
    end

    def_delegators :@chart, *%i(accounts account_balance apply_transaction balance fetch split_account)
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
      elsif id = params.delete(:id)
        return add_transaction_with_id(id, params)
      else
        transaction = build_transaction params
      end
      @transactions.push transaction
    end

    def add_transaction_with_id(id, params)
      @transaction_with_ids[id] = build_transaction params
    end

    def alter_transaction(id, effective_date: nil, scale: nil)
      orig = remove_transaction id
      old, new = orig.slice(effective_date - 1)
      old.each do |t| add_transaction t; end
      new_transaction = new.clone_transaction multiplier: scale
      add_transaction_with_id id, new_transaction
    end

    def fetch_transaction(id)
      @transaction_with_ids.fetch id
    end

    def remove_transaction(id)
      @transaction_with_ids.delete id
    end

    def each_transaction(&block)
      @transactions.each &block
      @transaction_with_ids.values.each(&block)
    end

    def balanced?
      balance.zero?
    end

    def net_worth
      @chart.net_worth.round(2).to_f
    end

    def project to: end_of_projection, build_next: false, &block
      must_be_balanced!
      projection = Projection.new range: (from..to), chart: @chart
      handler = TransactionHandler.new projection: projection
      if build_next
        handler.next_projector = self.class.new from: to + 1, chart: @chart
      end
      each_transaction do |transaction| handler << transaction; end
      projection.project! &block
      handler.next_projector
    end

    def transactions= transactions
      transactions.each do |transaction| add_transaction transaction; end
    end

    private

    def build_transaction params
      return params if params.is_a? Transaction
      klass = params.has_key?(:schedule) ? ScheduledTransaction : Transaction
      klass.new(params).tap do |transaction|
        validate_transaction! transaction
      end
    end

  end
end
