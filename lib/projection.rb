class Projection
  attr :accounts, :from, :projector, :running_balances, :to, :transactions
  private :running_balances

  class AccountBalance
    attr :balance, :opening_balance, :type

    def initialize balance, type
      @balance         = balance
      @opening_balance = balance
      @type            = type
    end

    def credit value
      @balance = balance.send add_or_deduct(:credit), value
    end

    def debit value
      @balance = balance.send add_or_deduct(:debit), value
    end

    private

    def add_or_deduct credit_or_debit
      should_add = {
        credit: %i(equity liability revenue),
        debit:  %i(asset expense),
      }.fetch(credit_or_debit)
      should_add ? :+ : :-
    end
  end

  def initialize projector, from: nil, to: nil
    @from             = from
    @projector        = projector
    @to               = to
    @transactions     = []
    @running_balances = build_running_balances
  end

  def account_balance account_id
    running_balances.fetch(account_id).balance
  end

  def accounts
    projector.accounts.each_with_object Hash.new do |(id, account), hash|
      hash[id] = Account.new(
        id,
        open_date:       account.open_date,
        opening_balance: running_balances.fetch(id).balance,
        parent_id:       account.parent_id,
        type:            account.type,
      )
    end
  end

  def initial_net_worth
    sum_balance_for_type(:opening_balance, :asset) - 
      sum_balance_for_type(:opening_balance, :liability)
  end

  def project
    projector.transactions.each do |transaction|
      new_transaction = transaction.apply! self do |credit_or_debit, amount, account_id|
        to_account_and_parents account_id do |account|
          running_balances.fetch(account.id).send credit_or_debit, amount
        end
      end
      transactions.push new_transaction if new_transaction
    end
  end

  def net_worth
    sum_balance_for_type(:balance, :asset) -
      sum_balance_for_type(:balance, :liability)
  end

  def net_worth_delta
    net_worth - initial_net_worth
  end

  def range
    (from..to)
  end

  private

  def account_ids_for_type type
    projector.accounts.select { |id, account| account.type == type }.map &:first
  end

  def build_running_balances
    projector.accounts.each_with_object Hash.new do |(id, account), hash|
      hash[id] = AccountBalance.new account.opening_balance, account.type
    end
  end

  def sum_balance_for_type balance_method, type
    account_ids_for_type(type).inject 0 do |sum, id|
      sum + running_balances.fetch(id).public_send(balance_method)
    end
  end

  def to_account_and_parents account_id
    while account_id
      account = projector.accounts.fetch account_id
      yield account
      account_id = account.parent_id
    end
  end

end
