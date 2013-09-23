class Transaction
  attr :credits, :debits, :schedule

  def initialize params = {}
    date = params.fetch :date
    @credits = Array params[:credits]
    @debits  = Array params[:debits]
    @credits << params[:credit] if params[:credit]
    @debits  << params[:debit]  if params[:debit]
    @schedule = build_schedule date, params[:schedule]
    freeze
  end

  def apply! projector, &block
    validate! projector
    if schedule.after? projector.range.end
      self
    else
      schedule.apply! self, projector.range, &block
    end
  end

  def validate! projector
    if schedule.before? projector.from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{projector.from} vs. #{schedule.date})"
    end
    unless schedule.transaction_balanced? self
      raise Projector::BalanceError, "Debits and credits do not balance"
    end
  end

  private

  def build_schedule date, params = {}
    if params.nil?
      OneTimeSchedule.new date
    else
      fetch_schedule_klass(params.fetch(:type)).new date, params
    end
  end

  def fetch_schedule_klass type
    classified_type = type.to_s
    classified_type.insert 0, '_'
    classified_type.gsub!(%r{_[a-z]}) { |match| match[1].upcase }
    classified_type.concat 'Schedule'
    self.class.const_get classified_type
  end

end
