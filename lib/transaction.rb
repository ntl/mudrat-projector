class Transaction
  attr :credits, :debits, :schedule

  class OneTimeSchedule
    attr :date

    def initialize date
      @date = date
      freeze
    end

    def after? other_date
      date > other_date
    end

    def apply! transaction, range, &block
      yield_over_each_bit transaction.credits, transaction.debits, &block
      nil
    end

    def before? other_date
      date < other_date
    end

    def recurring?
      false
    end

    def transaction_balanced? transaction
      credits, debits = total_credits_and_debits transaction
      credits == debits
    end

    private

    def yield_over_each_bit credits, debits, multiplier = 1
      credits.each do |amount, account_id|
        yield :credit, amount * multiplier, account_id
      end
      debits.each do |amount, account_id|
        yield :debit, amount * multiplier, account_id
      end
    end

    def total_credits_and_debits transaction
      credit_amounts = transaction.credits.map &:first
      debit_amounts  = transaction.debits.map  &:first
      sum_of = ->(integers) { integers.inject(0) { |s,i| s + i } }
      [sum_of.call(credit_amounts), sum_of.call(debit_amounts)]
    end
  end

  class CompoundSchedule < OneTimeSchedule
    attr :annual_interest, :initial_value, :months

    def initialize date, params = {}
      @annual_interest = params.fetch :annual_interest
      @initial_value   = params.fetch :initial_value
      @months          = params.fetch :months, nil
      super date
    end

    def apply! transaction, range, &block
      old_rounding_mode = BigDecimal.mode BigDecimal::ROUND_MODE
      BigDecimal.mode BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN

      if months.nil?
        months_amortized = DateDiff.date_diff(:month, [range.begin, date].max, range.end).to_i
        new_balance = initial_value * ((1 + rate) ** months_amortized)
        interest_paid  = new_balance - initial_value
        principal_paid = 0
        yield_over_each_bit(
          transaction.credits,
          transaction.debits,
          interest_paid.round(2),
          principal_paid.round(2),
          &block
        )
        Transaction.new(
          date:     range.end + 1,
          credits:  transaction.credits,
          debits:   transaction.debits,
          schedule: {
            annual_interest: annual_interest,
            initial_value:   new_balance,
            type:            :compound,
          },
        )
      else
        amortize range do |months_amortized, interest_paid, principal_paid|
          yield_over_each_bit(
            transaction.credits,
            transaction.debits,
            interest_paid.round(2),
            principal_paid.round(2),
            &block
          )
          new_balance = initial_value - principal_paid
          if new_balance.zero?
            nil
          else
            new_months = months ? months - months_amortized : nil
            Transaction.new(
              date:     range.end + 1,
              credits:  transaction.credits,
              debits:   transaction.debits,
              schedule: {
                annual_interest: annual_interest,
                initial_value:   new_balance,
                months:          new_months,
                type:            :compound,
              },
            )
          end
        end
      end
    ensure
      BigDecimal.mode BigDecimal::ROUND_MODE, old_rounding_mode
    end

    def monthly_payment
      iv  = initial_value
      r   = rate
      n   = months
      (iv * r) / (1 - ((1 + r) ** (-n)))
    end

    def rate
      annual_interest.to_d / 1200
    end

    def transaction_balanced? transaction
      true
    end

    private

    def amortize range, &block
      r  = rate
      mp = monthly_payment

      range_begin = [range.begin, date].max
      range_end   = [range.end,   final_month].min
      months_to_amortize = DateDiff.date_diff(:month, range_begin, range_end).to_i

      interest_paid  = 0
      principal_paid = 0

      months_to_amortize.times.inject initial_value do |balance, _|
        interest    = balance * r
        principal   = mp - interest
        interest_paid  += interest
        principal_paid += principal
        balance - principal
      end

      yield months_to_amortize, interest_paid, principal_paid
    end

    def fetch_account from: from, with_amount: with_amount
      hash = from.detect { |h| h.fetch(:amount) == with_amount }
      {}.fetch with_amount if hash.nil?
      hash.fetch :account
    end

    def final_month
      if months
        (date >> months) - 1
      else
        Projector::ABSOLUTE_END
      end
    end

    def yield_over_each_bit credits, debits, interest_paid, principal_paid, &block
      decode_amount_key = {
        interest:  interest_paid,
        principal: principal_paid,
        payment:   interest_paid + principal_paid,
      }
      credits.each do |credit|
        amount = decode_amount_key.fetch credit.fetch :amount
        yield :credit, amount, credit.fetch(:account)
      end
      debits.each do |debit|
        amount = decode_amount_key.fetch debit.fetch :amount
        yield :debit, amount, debit.fetch(:account)
      end
    end
  end

  class RecurringSchedule < OneTimeSchedule
    attr :end, :number, :unit
      
    def initialize date, params = {}
      @end    = params[:end] || Projector::ABSOLUTE_END
      @number = params.fetch :number
      @unit   = params.fetch :unit
      super date
    end

    def after? other_date
      date > other_date
    end

    def apply! transaction, range, &block
      yield_over_each_bit(
        transaction.credits,
        transaction.debits,
        calculate_range_multiplier(range),
        &block
      )
      remainder_transaction transaction, range
    end

    def before? other_date
      date < other_date
    end

    def to_hash
      {
        end:    self.end,
        number: number,
        type:   :recurring,
        unit:   unit,
      }
    end

    def recurring?
      true
    end

    private

    def calculate_range_multiplier range
      txn_start = [range.begin, date].max
      txn_end   = [range.end, self.end].min
      DateDiff.date_diff(unit: unit, from: txn_start, to: txn_end) * (1.0 / number)
    end

    def remainder_transaction transaction, range
      return nil if self.end <= range.end
      Transaction.new(
        date:     range.end + 1,
        credits:  transaction.credits,
        debits:   transaction.debits,
        schedule: to_hash,
      )
    end
  end

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
