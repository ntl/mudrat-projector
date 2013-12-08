module MudratProjector
  class TransactionHandler
    attr_accessor :next_projector

    def initialize projection: projection
      @projection = projection
    end

    def << transaction
      in_projection, leftover = transaction.slice @projection.range.end
      @projection.add_transaction_batch in_projection
      defer leftover if leftover
    end

    def defer transaction
      next_projector.add_transaction transaction if next_projector
    end
  end
end
