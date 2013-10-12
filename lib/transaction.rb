class Transaction
  include Enumerable

  attr :credits, :date, :debits

  def initialize params = {}
    @date        = params.fetch :date
    self.credits = extract_entry_params :credit, params
    self.debits  = extract_entry_params :debit,  params
  end

  def balanced?
    sum_credits = build_set_for_balance credits
    sum_debits  = build_set_for_balance debits
    (sum_credits ^ sum_debits).empty?
  end

  def credits= credits
    @credits = build_entries :credit, credits
  end

  def debits= debits
    @debits = build_entries :debit, debits
  end

  def each &block
    credits.each &block
    debits.each &block
  end

  def slice slice_date
    if date > slice_date
      [[], self]
    else
      [[self], nil]
    end
  end

  private

  def extract_entry_params credit_or_debit, params
    entries = Array params["#{credit_or_debit}s".to_sym]
    return entries unless params.has_key? credit_or_debit
    unless entries.empty?
      raise ArgumentError, "You cannot supply both #{credit_or_debit} and "\
        "#{credit_or_debit}s"
    end
    [params.fetch(credit_or_debit)]
  end

  def build_entries credit_or_debit, entries
    entries.map do |entry_params|
      if entry_params.is_a? TransactionEntry
        entry_params
      else
        TransactionEntry.public_send "new_#{credit_or_debit}", entry_params
      end
    end
  end

  def build_set_for_balance entries
    hash = Hash.new { |h,k| h[k] = 0 }
    entries.each do |entry|
      balance_key = entry.class == TransactionEntry ? :fixed : entry.other_account_id
      hash[balance_key] += entry.scalar
    end
    hash.reduce Set.new do |set, (_, value)| set << value; end
  end
end
