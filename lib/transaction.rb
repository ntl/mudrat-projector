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

  def reduce! projection
    validate! projection
    schedule.reduce self, projection.range
  end

  def after? date
    schedule.after? date
  end

  def each_entry
    credits.each { |entry| yield :credit, *entry }
    debits.each { |entry| yield :debit, *entry }
  end

  def credits_and_debits
    credits + debits
  end

  def validate! projector
    if schedule.before? projector.from
      raise Projector::InvalidTransaction, "Transactions cannot occur before "\
        "projection start date. (#{projector.from} vs. #{schedule.date})"
    end
    if [credits, debits].none? { |e| e.size == 1 }
      unless [credits, debits].all? { |e| e.empty? }
        raise Projector::InvalidTransaction, "Transactions cannot split on "\
          "both the credits and the debits"
      end
    end
    schedule.validate! self
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
