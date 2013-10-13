class TransactionEntry
  attr :account_id, :scalar

  module TransactionEntry::Factory
    def new params = {}
      catch :instance do
        maybe_build_new_fixed_entry params
        maybe_build_new_percentage_entry params
        super
      end
    end

    def new_credit params = {}
      params = { credit_or_debit: :credit }.merge params
      new params
    end

    def new_debit params = {}
      params = { credit_or_debit: :debit }.merge params
      new params
    end

    private

    def maybe_build_new_fixed_entry params
      return unless params.has_key? :amount
      params = params.dup
      params[:scalar] = params.delete :amount
      throw :instance, new(params).tap(&:calculate_amount)
    end

    def maybe_build_new_percentage_entry params
      return unless params.has_key?(:percent) && self == TransactionEntry
      params = params.dup
      params[:scalar] = params.delete :percent
      params[:other_account_id] = params.delete :of
      throw :instance, PercentageTransactionEntry.new(params)
    end
  end

  extend TransactionEntry::Factory

  def initialize params = {}
    @account_id      = params.fetch :account_id
    @scalar          = params.fetch :scalar
    @credit_or_debit = params.fetch :credit_or_debit
    validate!
  end

  def * multiplier
    return self if multiplier == 1
    self.class.new serialize.merge(scalar: scalar * multiplier)
  end

  def amount
    @amount
  end

  def calculate_amount chart_of_accounts = nil
    @amount = scalar
  end

  def credit?
    @credit_or_debit == :credit
  end

  def debit?
    @credit_or_debit == :debit
  end

  def inspect
    "#<#{self.class}: scalar=#{fmt(scalar)}, account_id=#{account_id.inspect} type=#{@credit_or_debit.inspect}>"
  end

  def serialize
    {
      account_id:       account_id,
      scalar:           scalar,
      credit_or_debit:  @credit_or_debit,
    }
  end

  def validate!
    if scalar == 0
      raise ArgumentError, "You cannot supply a scalar of 0"
    end
    unless %i(credit debit).include? @credit_or_debit
      raise ArgumentError, "Must supply :credit or :debit, not #{@credit_or_debit.inspect}"
    end
  end

  private

  def fmt number
    number.respond_to?(:round) ? number.round(2).to_f : number
  end
end

class PercentageTransactionEntry < TransactionEntry
  attr :other_account_id

  def initialize params = {}
    @other_account_id = params.fetch :other_account_id
    super params
  end

  def calculate_amount chart_of_accounts
    @amount = scalar * chart_of_accounts.fetch(other_account_id).balance
  end

  def inspect
    super.tap do |s|
      s.insert -2, ", other_account_id=#{other_account_id.inspect}"
    end
  end

  def serialize
    super.tap do |hash| hash[:other_account_id] = other_account_id; end
  end
end
