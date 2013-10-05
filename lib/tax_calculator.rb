class TaxCalculator
  attr :household, :projector, :year

  HOUSEHOLD_TYPES = %i(married_filing_jointly married_filing_separately single
                       head_of_household)

  EXPENSE_ACCOUNT_ID = :irs

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

  def deduction
    values_hash.fetch :standard_deduction
  end

  def exemption
    values_hash.fetch(:personal_exemption) * household.exemptions
  end

  def standard_deduction
    values_hash.fetch :standard_deduction
  end

  def medicare_ss
    (values_hash.fetch(:oasdi) + values_hash.fetch(:hi)) / 100
  end

  def project
    se_gross = 0
    w2_gross = 0

    @projection = projector.project to: Date.new(year, 12, 31) do |account, amount|
      if account.type == :revenue && account.tag?(:self_employed)
        se_gross += amount
      elsif account.type == :expense && account.tag?(:business)
        se_gross -= amount
      end
    end

    se_tax = se_gross * (1 - medicare_ss) * (medicare_ss * 2)

    gross = se_gross + w2_gross
    agi = gross

    agi -= se_tax / 2 # Deduction for half self employment tax paid
    agi -= deduction  # Standard/itemized deduction
    agi -= exemption  # Personal exemptions

    taxes = calculate_income_tax agi
    taxes += se_tax

    OpenStruct.new(
      effective_rate: ((taxes * 100) / gross).round(2),
      gross:          gross,
      net:            gross - taxes,
      taxes:          taxes,
      year:           year,
    )
  end

  def values_hash
    @values_hash ||= parse_yaml
  end

  def parse_yaml
    yaml = File.expand_path '../tax_values_by_year.yml', __FILE__
    parsed = YAML.load(File.read(yaml)).fetch(year).tap do |hash|
      recursively_symbolize_keys! hash
    end
    hash = parsed.fetch :single
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

  Household = Struct.new :filing_status, :exemptions
end
