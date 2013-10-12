class Projection
  attr :range

  def initialize range: date_range, chart: chart_of_accounts
    @chart                = chart
    @range                = range
    @transaction_sequence = []
  end

  def << transaction
    validate_transaction! transaction
    @transaction_sequence.push transaction
  end

  def project!
    freeze
    transaction_sequence.each do |transaction|
      @chart.apply_transaction transaction
      yield transaction if block_given?
    end
  end

  def transaction_sequence
    @transaction_sequence.sort do |a,b| a.date <=> b.date; end
  end

  def validate_transaction! transaction
    unless range.include? transaction.date
      raise Projector::InvalidTransaction, "Transaction date "\
        "#{transaction.date} falls outside of range #{range.inspect}"
    end
  end
end
