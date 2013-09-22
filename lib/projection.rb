class Projection
  attr :account_projections, :from, :projector, :to

  class AccountProjection
    attr :account, :balance_offset, :initial_balance, :range
    private :account, :balance_offset, :range

    def initialize range, account
      @range           = range
      @account         = account
      @initial_balance = account.opening_balance
      @balance_offset  = 0
    end

    def apply_credit amount
      asset_or_expense? ? deduct_from_balance(amount) : add_to_balance(amount)
    end

    def apply_debit amount
      asset_or_expense? ? add_to_balance(amount) : deduct_from_balance(amount)
    end

    def balance
      initial_balance + balance_offset
    end

    def delta
      [initial_balance, balance]
    end

    def name
      account.name
    end

    def open_date
      account.open_date
    end

    def parent_id
      account.parent_id
    end

    def type
      account.type
    end

    private

    def add_to_balance amount
      @balance_offset += amount
    end

    def asset_or_expense?
      %i(asset expense).include? type
    end

    def deduct_from_balance amount
      @balance_offset -= amount
    end
  end

  def initialize projector, from: nil, to: nil
    @from                = from
    @projector           = projector
    @to                  = to
    @account_projections = build_account_projections
    project
  end

  def accounts
    account_projections.each_with_object({}) do |(id, account_projection), hash|
      hash[id] = {
        open_date:       account_projection.open_date,
        opening_balance: account_projection.balance,
        parent_id:       account_projection.parent_id,
        name:            account_projection.name,
        type:            account_projection.type,
      }
    end
  end

  def asset_balances method = :balance
    asset_accounts = account_projections.values.select do |account_projection|
      account_projection.type == :asset
    end
    asset_accounts.map(&method.to_proc).inject(&:+)
  end

  def closing_equity
    asset_balances # - liability_balances, etc.
  end

  def opening_equity
    asset_balances :initial_balance # - liability_balances, etc.
  end

  def range
    (from..to)
  end

  def transactions
    projector.transactions.reject do |transaction|
      transaction_ends_in_range? transaction
    end
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

  def get_total_amount amount, transaction
    recurring_schedule = transaction.recurring_schedule
    if recurring_schedule
      txn_start = [range.begin, transaction.date].max
      txn_end   = [range.end, recurring_schedule.to].min
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

  def project
    projector.transactions.each do |transaction|
      next unless transaction_falls_in_range? transaction
      transaction.each_bit do |credit_or_debit, amount, account_id|
        account_projection = account_projections.fetch account_id
        total_amount = get_total_amount amount, transaction
        apply_transaction_bit credit_or_debit, total_amount, account_projection
      end
    end
  end

  def transaction_ends_in_range? transaction
    recurring_schedule = transaction.recurring_schedule
    if recurring_schedule
      recurring_schedule.to < to
    else
      transaction.date < to
    end
  end

  def transaction_falls_in_range? transaction
    recurring_schedule = transaction.recurring_schedule
    if recurring_schedule
      schedule_range = recurring_schedule.range
      if schedule_range.begin < range.begin && schedule_range.end > range.end
        true
      else
        range.include?(recurring_schedule.range.begin) ||
          range.include?(recurring_schedule.range.end)
      end
    else
      range.include? transaction.date
    end
  end
end
