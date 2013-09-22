class Projection
  attr :account_projections, :from, :projector, :to

  class AccountProjection
    attr :account, :balance, :initial_balance, :range
    private :account, :range

    def initialize range, account
      @range   = range
      @account = account
      @balance = 0
    end

    def apply_credit amount
      asset_or_expense? ? deduct_from_balance(amount) : add_to_balance(amount)
    end

    def apply_debit amount
      asset_or_expense? ? add_to_balance(amount) : deduct_from_balance(amount)
    end

    def delta
      [initial_balance, balance]
    end

    def initial_balance
      0
    end

    def name
      account.name
    end

    def parent_id
      account.parent_id
    end

    def type
      account.type
    end

    private

    def add_to_balance amount
      @balance += amount
    end

    def asset_or_expense?
      %i(asset expense).include? type
    end

    def deduct_from_balance amount
      @balance -= amount
    end
  end

  def initialize projector, from: nil, to: nil
    @from                = from
    @projector           = projector
    @to                  = to
    @account_projections = build_account_projections
  end

  def accounts
    account_projections
  end

  def asset_balances
    asset_accounts = account_projections.values.select do |account_projection|
      account_projection.type == :asset
    end
    asset_accounts.map(&:balance).inject(&:+)
  end

  def closing_equity
    asset_balances # - liability_balances
  end

  def opening_equity
    0
  end

  def project
    projector.transactions.each do |transaction|
      transaction.each_bit do |credit_or_debit, amount, account_id|
        account_projection = account_projections.fetch account_id
        total_amount = get_total_amount range, amount, transaction
        apply_transaction_bit credit_or_debit, total_amount, account_projection
      end
    end
  end

  def range
    (from..to)
  end

  private

  def apply_transaction_bit method, amount, account_projection
    while account_projection
      account_projection.send "apply_#{method}", amount
      _, account_projection = account_projections.detect do |id, ap|
        id == account_projection.parent_id
      end
    end
  end

  def build_account_projections
    projector.accounts.each_with_object Hash.new do |(id, account), hash|
      hash[id] = AccountProjection.new(range, account)
    end
  end

  def get_total_amount range, amount, transaction
    recurring_schedule = transaction.recurring_schedule
    if recurring_schedule
      txn_start = [range.begin, transaction.date].max
      txn_end   = [range.end, recurring_schedule.end].min
      [
        amount,
        DateDiff.date_diff(
          unit: recurring_schedule.unit,
          from: txn_start,
          to:   txn_end,
        ),
        (1.0 / recurring_schedule.number),
      ].inject { |a,v| a * v }
    else
      amount
    end
  end
end