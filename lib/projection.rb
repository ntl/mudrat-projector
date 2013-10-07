class Projection
  attr :range, :projector

  def initialize source_projector, range: nil, next_projector: nil
    @source_projector = source_projector
    @projector        = next_projector
    @range            = range
  end

  def project!
    @source_projector.transactions.each do |transaction|
      if transaction.after? range.end
        projector.add_transaction transaction

      elsif transaction.scheduled?
        next_transaction = transaction.advance(until: range.end) do |entry|
          handle_entry entry
        end
        projector.add_transaction next_transaction if next_transaction

      else
        transaction.each_entry do |entry|
          handle_entry entry
        end

      end
    end
  end

  def handle_entry entry
    account = projector.accounts.fetch entry.account_id
    while account
      account.apply_transaction_entry! entry
      account = projector.accounts[account.parent_id]
    end
  end
end
