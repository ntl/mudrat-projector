class TaxCalculator
  extend Forwardable

  module Year2012
    # see http://en.wikipedia.org/wiki/Tax_Relief,_Unemployment_Insurance_Reauthorization,_and_Job_Creation_Act_of_2010
    def social_security_withheld
      super * (4.2.to_d / 6.2.to_d)
    end
  end

  attr :household, :projector, :year

  HOUSEHOLD_TYPES = %i(married_filing_jointly married_filing_separately single
                       head_of_household)
  EXPENSE_ACCOUNT_ID = :united_states_treasury

  Household = Struct.new :filing_status, :exemptions

  def initialize projector: nil, household: {}
    @household   = Household.new(
      household.fetch(:filing_status),
      household.fetch(:exemptions),
    )
    @projector   = projector
    @year        = @projector.from.year
    @values_hash = parse_yaml
    projector.add_account EXPENSE_ACCOUNT_ID, type: :expense
    extend_year_shim
  end

  def extend_year_shim
    shim_module = "Year#{year}".to_sym
    if TaxCalculator.const_defined? shim_module
      extend TaxCalculator.const_get shim_module
    end
  end
  private :extend_year_shim

  def method_missing method_name, *args
    if args.empty? && @values_hash.has_key?(method_name)
      @values_hash.fetch method_name
    else
      super
    end
  end

  def adjustments
    self_employment_tax / 2
  end

  def agi
    gross - adjustments
  end

  def brackets
    bracket_caps = values_hash.fetch(:brackets).tap do |list|
      list.push Float::INFINITY
    end
    values_hash.fetch(:bracket_rates).zip bracket_caps
  end

  def calculate!
    se_gross = 0
    w2_gross = 0
    projector.project to: Date.new(year, 12, 31) do |transaction|
      transaction.credits.each do |entry|
        account = projector.fetch entry.account_id
        if account.type == :revenue
          w2_gross += entry.amount if account.tag? :salary
          se_gross += entry.amount if account.tag? :self_employed
        end
      end
      transaction.debits.each do |entry|
        account = projector.fetch entry.account_id
        if account.type == :expense && account.tag?(:self_employed)
          se_gross -= entry.amount
        end
      end
    end
    @se_gross = se_gross
    @w2_gross = w2_gross
    @gross = se_gross + w2_gross
    self
  end

  def deduction
    standard_deduction
  end

  def effective_rate
    (((gross - net) / gross) * 100).round 2
  end

  def exemption
    personal_exemption * household.exemptions
  end

  def gross
    @gross
  end
  alias_method :total_income, :gross

  def income_tax
    amount_taxed = 0
    brackets.reduce 0 do |sum, (rate, cap)|
      if cap == Float::INFINITY
        in_bracket = taxable_income - amount_taxed
      else
        in_bracket = [cap, taxable_income].min - amount_taxed
      end
      amount_taxed += in_bracket
      t = (in_bracket * (rate / 100))
      sum + t
    end
  end

  def medicare_withheld
    @w2_gross * (hi_rate / 100)
  end

  def net
    gross - taxes
  end

  def self_employment_tax
    rate = (oasdi_rate + hi_rate) / 100
    @se_gross * (1 - rate) * (rate * 2)
  end

  def social_security_withheld
    [@w2_gross, oasdi_wage_base].min * (oasdi_rate / 100)
  end

  def taxable_income
    agi - deduction - exemption
  end

  def taxes
    withholding_tax + income_tax + self_employment_tax
  end

  def withholding_tax
    medicare_withheld + social_security_withheld
  end

  private

  def values_hash
    @values_hash ||= parse_yaml
  end

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


__END__
  attr :household, :projector, :year

  HOUSEHOLD_TYPES = %i(married_filing_jointly married_filing_separately single
                       head_of_household)

  def initialize projector: nil, household: nil
    @household = household
    @projector = projector
    @year  = projector.from.year

    projector.add_account EXPENSE_ACCOUNT_ID, type: :expense
  end

  def brackets
    bracket_caps = values_hash.fetch(:brackets).tap do |list|
      list.push Float::INFINITY
    end
    values_hash.fetch(:bracket_rates).zip bracket_caps
  end

  def calculate_income_tax amount
    amount_taxed = 0
    brackets.reduce 0 do |sum, (rate, cap)|
      in_bracket = [cap, amount].min - amount_taxed
      amount_taxed += in_bracket
      t = (in_bracket * (rate / 100))
      sum + t
    end
  end

  def deduction itemized_deduction
    standard = values_hash.fetch :standard_deduction
    [standard, itemized_deduction].max
  end

  def exemption
    values_hash.fetch(:personal_exemption) * household.exemptions
  end

  def standard_deduction
    values_hash.fetch :standard_deduction
  end

  def employee_medicare_ss
    value = employer_medicare_ss
    value -= 0.02 if [2011, 2012].include? year
    value
  end

  def employer_medicare_ss
    medicare = values_hash.fetch :hi
    ss       = values_hash.fetch :oasdi
    (medicare + ss) / 100.0
  end

  def self_employment_tax
    employee_medicare_ss + employer_medicare_ss
  end

  def calculate_se_tax gross
    gross * (1 - employer_medicare_ss) * self_employment_tax
  end

  def calculate_w2_medicare_ss gross
    wage_base     = values_hash.fetch :oasdi_wage_base
    medicare_only = values_hash.fetch(:hi) / 100

    under_wage_base = [gross, wage_base].min
    over_wage_base  = [gross - wage_base, 0].max

    (under_wage_base * employee_medicare_ss) + (over_wage_base * medicare_only)
  end

  def hsa_deductions hash
    hash.reduce [0, 0] do |(atl, pretax), (_, account)|
      atl_amount = account.fetch :amount
      pre_amount = account.fetch(:pretax) ? atl_amount : 0
      [atl + atl_amount, pretax + pre_amount]
    end
  end

  def hsa_cap account
    hsa_limits = values_hash.fetch :hsa_limit
    cap =
      if account.tag? :individual
        hsa_limits.fetch :individual
      elsif account.tag? :family
        hsa_limits.fetch :family
      else
        fail "hsa accounts need a family or individual tag"
      end
    cap += hsa_limits.fetch(:senior) if account.tag?(:senior)
    cap
  end

  def project
    se_gross = 0
    w2_gross = 0
    pretax   = 0
    hsa      = {}
    itemized = 0

    @projection = projector.project to: Date.new(year, 12, 31)
    @projection.reduced_transactions.each do |transaction|
      # FIXME: THIS BAD
      pretax = transaction.credits.size == 1 && transaction.debits.size == 2
      transaction.each_entry do |credit_or_debit, amount, account_id|
        account = projector.accounts.fetch account_id
        if account.tag? :self_employed
          if account.type == :revenue
            se_gross += amount
          elsif account.type == :expense
            se_gross -= amount
          end
        elsif account.tag?(:w2) && account.type == :revenue
          w2_gross += amount
        elsif account.tag?(:hsa) && account.type == :asset
          cap = hsa_cap account
          hsa[account.id] ||= { amount: 0, pretax: pretax }
          hsa[account.id][:amount] = [hsa[account.id][:amount] + amount, cap].min
        elsif account.tag?(:'501c') && account.type == :expense
          itemized += amount
        end
      end
    end

    gross = se_gross + w2_gross
    atl, pretax = hsa_deductions hsa

    se_tax         = calculate_se_tax se_gross
    w2_medicare_ss = calculate_w2_medicare_ss(w2_gross - pretax)

    agi = gross - atl - ((se_tax / 2) + deduction(itemized) + exemption)
    taxes = calculate_income_tax agi
    taxes += w2_medicare_ss
    taxes += se_tax

    OpenStruct.new(
      effective_rate: ((taxes * 100) / gross).round(2),
      gross:          gross,
      net:            gross - taxes,
      taxes:          taxes,
      year:           year,
    )
  end

end
