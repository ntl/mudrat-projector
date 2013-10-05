class Projection
  attr :accounts, :from, :projector, :to, :transactions

  attr :running_balances, :transaction_callback
  private :running_balances, :transaction_callback

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

    def delta
      balance - opening_balance
    end

    private

    def add_or_deduct credit_or_debit
      should_add = {
        credit: %i(equity liability revenue),
        debit:  %i(asset expense),
      }.fetch(credit_or_debit)
      should_add.include?(type) ? :+ : :-
    end
  end

  def initialize projector, from: nil, to: nil, transaction_callback: nil
    @from             = from
    @projector        = projector
    @running_balances = build_running_balances
    @to               = to
    @transactions     = []
    @transaction_callback = transaction_callback
  end

  def account_balance account_id
    running_balances.fetch(account_id).balance
  end

  def account_ids
    running_balances.keys
  end

  def accounts
    projector.accounts.each_with_object Hash.new do |(id, account), hash|
      new_opening_balance = account_balance id
      hash[id] = Account.new(
        id,
        open_date:       account.open_date,
        opening_balance: new_opening_balance,
        parent_id:       account.parent_id,
        type:            account.type,
      )
    end
  end

  def delta account_id
    running_balances.fetch(account_id).delta
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
          transaction_callback.(account, amount) if transaction_callback
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

  def build_running_balances
    projector.accounts.each_with_object Hash.new do |(id, account), hash|
      hash[id] = AccountBalance.new account.opening_balance, account.type
    end
  end

  def sum_balance_for_type balance_method, type
    running_balances.inject 0 do |sum, (id, account_balance)|
      if account_balance.type == type
        sum + running_balances.fetch(id).public_send(balance_method)
      else
        sum
      end
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
