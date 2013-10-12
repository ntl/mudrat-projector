class ChartOfAccounts
  include Enumerable

  def initialize
    @accounts = {}
  end

  def add_account id, **params
    @accounts[id] = Account.new params
  end

  def apply_transaction transaction
    validate_transaction! transaction
    transaction.entries.each do |entry|
      entry.calculate_amount self
      fetch(entry.account_id).add_entry entry
    end
    transaction
  end

  def balance
    inject 0 do |sum, account|
      if account.parent?
        sum
      else
        method = %i(asset expense).include?(account.type) ? :+ : :-
        sum.public_send method, account.balance
      end
    end
  end

  def each &block
    @accounts.values.each &block
  end

  def fetch account_id
    @accounts.fetch account_id
  end

  def net_worth
    @accounts.reduce 0 do |sum, (_, account)|
      if account.type == :asset
        sum + account.balance
      elsif account.type == :liability
        sum - account.balance
      else
        sum
      end
    end
  end

  def size
    @accounts.size
  end

  def serialize
    @accounts.reduce Hash.new do |hash, (id, account)|
      hash[id] = account.serialize
      hash
    end
  end

  def split_account id, into: {}
    parent = fetch id
    into.each do |sub_account_id, hash|
      @accounts[sub_account_id] = 
        if hash
          parent.create_child(
            opening_balance: hash[:amount],
            parent_id: id,
            tags: hash[:tags],
          )
        else
          parent.create_child parent_id: id
        end
    end
  end

  def validate_transaction! transaction
    transaction.each do |entry|
      validate_entry! transaction.date, entry
    end
  end

  def validate_entry! transaction_date, entry
    unless @accounts.has_key? entry.account_id
      raise Projector::AccountDoesNotExist, "Transaction references non "\
        "existent account #{entry.account_id.inspect}"
    end
    open_date = fetch(entry.account_id).open_date
    unless open_date < transaction_date
      raise Projector::AccountDoesNotExist, "Transaction references account "\
        "#{entry.account_id.inspect} which does not open until #{open_date}, "\
        "but transaction is set for #{transaction_date}"
    end
  end
end
