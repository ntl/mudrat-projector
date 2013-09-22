class Projection
  attr :account_projections, :from, :projector, :to, :transactions

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
    @transactions        = []
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

  def accounts_by_type type
    account_projections.values.select { |ap| ap.type == type }
  end

  def account_type_balance type, initial = false
    method_name = initial ? :initial_balance : :balance
    accounts_by_type(type).map(&method_name).inject 0, &:+
  end

  def initial_net_worth
    account_type_balance(:asset, true)  - account_type_balance(:liability, true)
  end

  def project
    projector.transactions.each do |transaction|
      new_transaction = transaction.apply! self do |credit_or_debit, amount, account_id|
        account_projection = account_projections.fetch account_id
        apply_transaction_bit credit_or_debit, amount, account_projection
      end
      transactions.push new_transaction if new_transaction
    end
  end

  def net_worth
    account_type_balance(:asset) - account_type_balance(:liability)
  end

  def net_worth_delta
    net_worth - initial_net_worth
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
end
