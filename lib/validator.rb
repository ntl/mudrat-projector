class Validator
  attr :chart, :projector

  def initialize projector: projector, chart: chart
    @projector = projector
    @chart     = chart
  end

  def must_be_balanced!
    unless projector.balanced?
      raise Projector::BalanceError, "Cannot project unless the accounts "\
        "are in balance"
    end
  end

  def validate_account! account_id, params
    if chart.exists? account_id
      raise Projector::AccountExists, "Account #{account_id.inspect} exists"
    end
    unless Account::TYPES.include? params[:type]
      raise Projector::InvalidAccount, "Account #{account_id.inspect} has "\
        "invalid type #{params[:type].inspect}"
    end
    if params.has_key?(:open_date) && params[:open_date] > projector.from
      if params.has_key? :opening_balance
        raise Projector::InvalidAccount, "Account #{account_id.inspect} opens "\
          "after projector, but has an opening balance"
      end
    end
  end

  def validate_transaction! transaction
    if transaction.date < projector.from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{projector.from} vs. #{transaction.date})"
    end
    unless transaction.balanced?
      raise Projector::BalanceError, "Credits and debit entries both "\
        "must be supplied; they cannot amount to zero"
    end
    if transaction.credits.empty? || transaction.debits.empty?
      raise Projector::InvalidTransaction, "You must supply at least a debit "\
        "and a credit on each transaction"
    end
  end

end
