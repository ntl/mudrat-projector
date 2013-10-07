class Transaction
  attr :credits, :date, :debits

  def self.new params = {}
    if params.has_key?(:schedule) && self == Transaction
      ScheduledTransaction.new params
    else
      super params
    end
  end

  def initialize params = {}
    @date    = params.fetch :date
    @credits = build_frozen_entries :credit, params
    @debits  = build_frozen_entries :debit, params
    validate!
  end

  def after? other_date
    date > other_date
  end

  def before? other_date
    date < other_date
  end

  def each_entry &block
    credits.each &block
    debits.each &block
  end

  def scheduled?
    is_a? ScheduledTransaction
  end

  def validate!
    balance = 0
    each_entry do |entry|
      balance = entry.credit? ? balance - entry.amount : balance + entry.amount
    end
    unless balance == 0
      raise Projector::BalanceError, "Debits and credits do not balance"
    end
    if credits.size > 1 && debits.size > 1
      raise Projector::InvalidTransaction, "Transactions cannot split on both "\
        "the credits and the debits"
    end
  end

  private

  def build_frozen_entries key, params
    entries = params.fetch "#{key}s".to_sym do Array.new; end
    entries.push params[key] if params.has_key? key
    entries.map do |entry|
      if entry.is_a? TransactionEntry
        entry
      else
        TransactionEntry.new(key, *entry).tap &:freeze
      end
    end
  end
end

class ScheduledTransaction < Transaction
  attr :schedule, :type

  def initialize params
    params = params.dup
    schedule_params = params.delete :schedule
    super params
    if schedule_params.is_a? Hash
      @type     = schedule_params.delete :type
      @schedule = fetch_subclass(type).new date, schedule_params
    else
      @schedule = schedule_params
    end
  end

  def fetch_subclass type
    classified_type = type.to_s
    classified_type.insert 0, '_'
    classified_type.gsub!(%r{_[a-z]}) { |match| match[1].upcase }
    classified_type.concat 'Schedule'
    self.class.const_get classified_type
  end

  def advance **params, &block
    range = (date..params.fetch(:until))
    transaction, next_scheduled_transaction = schedule.advance self, over: range
    transaction.each_entry &block
    next_scheduled_transaction
  end
end

TransactionEntry = Struct.new :credit_debit, :amount, :account_id do
  def initialize *args
    super
    freeze
  end

  def credit?
    credit_debit == :credit
  end

  def debit?
    credit_debit == :debit
  end

  def inspect
    "<##{self.class}: #{credit_debit} #{amount.round(2).to_f.inspect} #{account_id.inspect}>"
  end
end
