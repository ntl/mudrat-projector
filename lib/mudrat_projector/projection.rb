module MudratProjector
  class Projection
    attr :range

    SequenceEntry = Struct.new :transaction, :batch_id do
      def sort_key
        [transaction.date, batch_id]
      end

      def <=> other_entry
        sort_key <=> other_entry.sort_key
      end
    end

    def initialize range: date_range, chart: chart_of_accounts
      @chart                = chart
      @batch_id             = 0
      @range                = range
      @transaction_sequence = []
    end

    def << transaction
      @transaction_sequence.push SequenceEntry.new(transaction, @batch_id)
    end

    def add_transaction_batch batch
      batch.each do |transaction| 
        self << transaction
        @batch_id += 1
      end
    end

    def project!
      freeze
      transaction_sequence.each do |transaction|
        @chart.apply_transaction transaction
        yield transaction if block_given?
      end
    end

    def transaction_sequence
      @transaction_sequence.tap(&:sort!).map &:transaction
    end
  end
end
