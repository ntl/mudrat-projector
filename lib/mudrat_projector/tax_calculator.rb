module MudratProjector
  class TaxCalculator
    module Year2012
      # see http://en.wikipedia.org/wiki/Tax_Relief,_Unemployment_Insurance_Reauthorization,_and_Job_Creation_Act_of_2010
      def social_security_withheld
        super * (4.2.to_d / 6.2.to_d)
      end
    end

    attr :household, :projector

    HOUSEHOLD_TYPES = %i(married_filing_jointly married_filing_separately single
                         head_of_household)
    EXPENSE_ACCOUNT_ID = :united_states_treasury

    Household = Struct.new :filing_status, :exemptions do
      def initialize *args
        super
        unless HOUSEHOLD_TYPES.include? filing_status
          raise "Invalid filing status #{filing_status.inspect}"
        end
      end
    end

    def self.project projector, to: end_date, household: nil
      tax_calculator = new projector: projector, household: household
      (projector.from.year..to.year).each do
        calculation = tax_calculator.calculate!
        yield calculation if block_given?
      end
      tax_calculator.projector
    end

    class TransactionWrapper
      INCOME_VALUES      = %i(business_profit dividend_income salaries_and_wages)
      ADJUSTMENTS_VALUES = %i(other_adjustments)
      DEDUCTIONS_VALUES  = %i(charitable_contributions interest_paid taxes_paid)
      CREDITS_VALUES     = %i()

      VALUES = [INCOME_VALUES, ADJUSTMENTS_VALUES, DEDUCTIONS_VALUES, CREDITS_VALUES].flatten 1

      attr :calculator, :taxes_withheld
      private :calculator

      def initialize calculator, transaction
        @calculator = calculator
        @taxes_withheld = 0
        @transaction = transaction
        VALUES.each do |attr_name| instance_variable_set "@#{attr_name}", 0; end
      end

      VALUES.each do |attr_name| attr attr_name; end

      def calculate!
        @transaction.entries.each do |entry|
          account = calculator.projector.fetch entry.account_id
          if account.type == :revenue
            @salaries_and_wages += entry.delta if account.tag? :salary
            @business_profit    += entry.delta if account.tag? :self_employed
            @dividend_income    += entry.delta if account.tag? :dividend
          elsif account.type == :expense
            @business_profit    -= entry.delta if account.tag? :self_employed
            @charitable_contributions +=
                                   entry.delta if account.tag? "501c".to_sym
            @interest_paid      += entry.delta if account.tag? :mortgage_interest
            @taxes_paid         += entry.delta if account.tag? :tax
            @taxes_withheld     += entry.delta if entry.account_id == EXPENSE_ACCOUNT_ID
          elsif account.type == :asset
            @other_adjustments  += entry.delta if account.tag?(:hsa) && entry.debit?
          end
        end
      end
      
      def debits
        @transaction.debits
      end

      def credits
        @transaction.credits
      end
    end

    def initialize projector: nil, household: {}
      @household   = Household.new(
        household.fetch(:filing_status),
        household.fetch(:exemptions),
      )
      @projector   = projector
      @values_hash = parse_yaml
      unless projector.account_exists? EXPENSE_ACCOUNT_ID
        projector.add_account EXPENSE_ACCOUNT_ID, type: :expense
      end
      unless projector.account_exists? :owed_taxes
        projector.add_account :owed_taxes, type: :liability
      end
    end

    def calculate!
      end_of_calendar_year = Date.new year, 12, 31
      calculation = TaxCalculation.new projector, household, @values_hash
      next_projector = projector.project to: end_of_calendar_year, build_next: true do |transaction|
        calculation << TransactionWrapper.new(self, transaction).tap(&:calculate!)
      end
      final_transaction = Transaction.new(
        date: end_of_calendar_year,
        debit:  { amount: calculation.taxes_owed, account_id: EXPENSE_ACCOUNT_ID },
        credit: { amount: calculation.taxes_owed, account_id: :owed_taxes },
      )
      projector.apply_transaction final_transaction
      @projector = next_projector
      @values_hash = parse_yaml
      calculation
    end

    def year
      projector.from.year
    end

    private

    def parse_yaml
      yaml = File.expand_path '../tax_values_by_year.yml', __FILE__
      by_year = YAML.load File.read(yaml)
      max_year = by_year.keys.max
      parsed = by_year.fetch([year, max_year].min).tap do |hash|
        recursively_symbolize_keys! hash
      end
      hash = parsed.fetch household.filing_status
      parsed.each_with_object hash do |(key, value), hash|
        hash[key] = value unless HOUSEHOLD_TYPES.include? key
      end
      hash
    end

    def recursively_symbolize_keys! hash
      hash.keys.each do |key|
        value = hash.delete key
        recursively_symbolize_keys! value if value.is_a? Hash
        key = key.respond_to?(:to_sym) ? key.to_sym : key
        hash[key] = value
      end
    end
  end
end
