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

  class TransactionWrapper
    INCOME_VALUES      = %i(business_profit salaries_and_wages)
    ADJUSTMENTS_VALUES = %i(other_adjustments)
    DEDUCTIONS_VALUES  = %i(charitable_contributions interest_paid taxes_paid)
    CREDITS_VALUES     = %i()

    VALUES = [INCOME_VALUES, ADJUSTMENTS_VALUES, DEDUCTIONS_VALUES, CREDITS_VALUES].flatten 1

    attr :calculator
    private :calculator

    def initialize calculator, transaction
      @calculator = calculator
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
        elsif account.type == :expense
          @business_profit    -= entry.delta if account.tag? :self_employed
          @charitable_contributions +=
                                 entry.delta if account.tag? "501c".to_sym
          @interest_paid      += entry.delta if account.tag? :mortgage_interest
          @taxes_paid         += entry.delta if account.tag? :tax
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
    projector.add_account EXPENSE_ACCOUNT_ID, type: :expense
  end

  def calculate!
    calculation = TaxCalculation.new projector, household, @values_hash
    projector.project to: Date.new(year, 12, 31) do |transaction|
      calculation << TransactionWrapper.new(self, transaction).tap(&:calculate!)
    end
    calculation
  end

  def year
    projector.from.year
  end

  private

  def parse_yaml
    yaml = File.expand_path '../tax_values_by_year.yml', __FILE__
    parsed = YAML.load(File.read(yaml)).fetch(year).tap do |hash|
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
