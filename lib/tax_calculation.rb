class TaxCalculation
  attr :values_hash
  attr :w2_gross, :se_gross, :pretax_deductions, :other_gross
  attr :projector, :household, :taxes_withheld

  def initialize projector, household, values_hash
    @values_hash = values_hash
    @projector = projector
    @w2_gross = 0
    @se_gross = 0
    @pretax_deductions = 0
    @hsa_contribs = Hash.new { |h,k| h[k] = 0 }
    @household = household
    @itemized_deduction = 0
    @taxes_withheld = 0
    @other_gross = 0
    extend_year_shim
  end

  def method_missing method_name, *args
    if args.empty? && values_hash.has_key?(method_name)
      values_hash.fetch method_name
    else
      super
    end
  end

  def << transaction
    @w2_gross += transaction.salaries_and_wages
    @se_gross += transaction.business_profit
    @other_gross += transaction.dividend_income
    @itemized_deduction += transaction.charitable_contributions
    @itemized_deduction += transaction.interest_paid
    @itemized_deduction += transaction.taxes_paid
    @taxes_withheld     += transaction.taxes_withheld
    transaction.debits.each do |entry|
      account = projector.fetch entry.account_id
      if account.type == :asset && account.tag?(:hsa)
        revenue = transaction.credits.select { |e| a = projector.fetch(e.account_id); a.type == :revenue && a.tag?(:salary)}
        @pretax_deductions += revenue.reduce 0 do |s,e| s + e.amount; end
        @hsa_contribs[account] += [entry.amount - pretax_deductions, 0].max
      end
    end
  end

  def adjustments
    (self_employment_tax / 2) + hsa_contributions
  end

  def agi
    total_income - adjustments
  end

  def brackets
    bracket_caps = super.tap do |list|
      list.push Float::INFINITY
    end
    values_hash.fetch(:bracket_rates).zip bracket_caps
  end

  def deduction
    [itemized_deduction, standard_deduction].max
  end

  def effective_rate
    (((gross - net) / gross) * 100).round 2
  end

  def exemption
    personal_exemption * household.exemptions
  end

  def gross
    w2_gross + se_gross + other_gross
  end

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

  def hsa_contributions
    @hsa_contribs.reduce 0 do |sum, (account, amount)|
      type = [:individual, :family, :senior].detect { |tag| account.tag? tag }
      max = hsa_limit.fetch type
      sum + [amount, max].min
    end
  end

  def itemized_deduction
    @itemized_deduction
  end

  def medicare_withheld
    w2_gross * (hi_rate / 100)
  end

  def net
    gross - taxes
  end

  def self_employment_tax
    rate = (oasdi_rate + hi_rate) / 100
    se_gross * (1 - rate) * (rate * 2)
  end

  def social_security_withheld
    [w2_gross, oasdi_wage_base].min * (oasdi_rate / 100)
  end

  def taxable_income
    agi - deduction - exemption
  end

  def taxes
    withholding_tax + income_tax + self_employment_tax
  end

  def taxes_owed
    taxes - taxes_withheld
  end

  def total_income
    gross - pretax_deductions
  end

  def year
    projector.from.year
  end

  def withholding_tax
    medicare_withheld + social_security_withheld
  end

  private

  def extend_year_shim
    shim_module = "Year#{year}".to_sym
    if TaxCalculator.const_defined? shim_module
      extend TaxCalculator.const_get shim_module
    end
  end
end
