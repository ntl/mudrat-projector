class TaxCalculator
  attr :amount_taxed, :exemptions, :filing_status, :income_sources, :expenses,
    :property, :year, :hsa_bank_account_ids

  UnsupportedYear = Class.new StandardError

  FILING_STATUSES = %i(single married_filing_jointly married_filing_separately
                       head_of_household)

  def initialize(household: nil, year: Time.now.year, income_sources: nil, expenses: nil, property: nil, second_property: nil, hsa_bank_account_ids: nil)
    module_name = "Year#{year}"
    begin
      module_for_year = self.class.const_get module_name
    rescue NameError
      raise UnsupportedYear, "Year `#{year}' not supported"
    end

    class << self
      attr_accessor :standard_deductions, :tax_brackets, :medicare_ss, :exemption, :itemized_deductions_categories
    end

    extend module_for_year

    @year           = year
    @exemptions     = household.exemptions
    @filing_status  = household.filing_status.to_sym
    @property       = property || nil
    @hsa_bank_account_ids = hsa_bank_account_ids || []
    @expenses       = expenses || {}

    @income_sources = income_sources ||
      begin
        IncomeSource.includes(:transaction).map do |income_source|
          {
            name:           income_source.transaction.name,
            annual_gross:   income_source.gross_annual,
            tax_form:       income_source.tax_form,
            pay_interval:   income_source.pay_interval,
            paycheck_gross: income_source.gross_paycheck,

            transaction:    income_source.transaction,
            record:         income_source,
          }
        end
      end

    @income_sources.map! { |hash| OpenStruct.new hash }

    @income_sources.sort! do |a,b|
      if a.tax_form == b.tax_form
        b.annual_gross <=> a.annual_gross
      else
        b.tax_form == 'w2' ? 1 : -1
      end
    end

    @amount_taxed = 0
    deductions_offset = above_the_line_deductions + deduction + exemption_total
    self.income_sources.each do |income_source|
      to_paycheck = ->(amount) { amount }
      taxable = [income_source.annual_gross - deductions_offset, 0].max
      deductions_offset -= income_source.annual_gross - taxable

      income_taxes = incremental_income_taxes(
        taxable,
        amount_taxed,
      )
      medicare, ss = incremental_medicare_ss(
        income_source.annual_gross,
        income_source.tax_form,
        amount_taxed,
      )

      income_source.taxable = taxable.round(2).to_f

      income_source.annual_income_taxes   = income_taxes
      income_source.annual_medicare       = medicare
      income_source.annual_ss             = ss
      income_source.annual_taxes          = income_taxes + medicare + ss
      income_source.annual_net            = income_source.annual_gross - \
                                              income_source.annual_taxes
      
      income_source.paycheck_income_taxes = to_paycheck.call income_taxes
      income_source.paycheck_medicare     = to_paycheck.call medicare
      income_source.paycheck_ss           = to_paycheck.call ss
      income_source.paycheck_taxes        = to_paycheck.call \
                                              income_source.annual_taxes
      income_source.paycheck_net          = to_paycheck.call \
                                              income_source.annual_net
      income_source.effective_rate        = (
        100.0 * ( \
          1 - (income_source.annual_net / income_source.annual_gross)
        )
      ).round(2).to_f

      @amount_taxed += taxable
    end
  end

  def breakdown
    {
      tax_year: year,
      income_sources: income_sources.map { |is|
        {
          name: is.name,
          income_tax: {
            annual: is.annual_income_taxes,
            paycheck: is.paycheck_income_taxes,
          },
          medicare: {
            annual: is.annual_medicare,
            paycheck: is.paycheck_medicare,
          },
          ss: {
            annual: is.annual_ss,
            paycheck: is.paycheck_ss,
          },
          gross: {
            annual: is.annual_gross,
            paycheck: is.paycheck_gross,
          },
        }
      },
      gross: {
        annual: gross,
        per_month: gross_monthly,
      },
      deductions: {
        above_the_line: above_the_line_deductions,
        below_the_line: deduction,
        exemptions: exemption_total,
      },
      net: {
        annual: net_income,
        per_month: net_monthly,
      },
    }.tap do |h|
      recursively_round = ->(hash) {
        hash.each do |k,v|
          if v.is_a?(Hash)
            recursively_round.call v
          elsif v.is_a?(Array)
            hash[k] = v.map { |e| recursively_round.call e }
          elsif v.is_a?(Numeric)
            hash[k] = v.round(2).to_f
          end
        end
      }
      recursively_round.call h
      h[:tax_year] = h[:tax_year].to_i
    end
  end

  def property_bonus
    taxable = [itemized_deductions_from_properties - (standard_deduction - itemized_deductions_from_expenses), 0].max
    annual = incremental_income_taxes taxable, amount_taxed
    annual / 12.0
  end

  def agi
    gross - above_the_line_deductions
  end

  def agi_floor(percent)
    agi * (percent / 100.to_f)
  end

  def gross
    income_sources.inject(0) { |sum, is| sum += is.annual_gross }.to_f
  end

  def taxes_paid
    income_sources.inject 0.0 do |sum, is|
      sum + is.annual_taxes
    end
  end

  def gross_monthly
    gross / 12.0
  end

  def net_monthly
    net_income / 12.0
  end

  def effective_rate
    ((1 - (net_income / gross)) * 100).round(2).to_f
  end

  def incremental_income_taxes(income, amount_already_taxed)
    income_tax_brackets.inject(0) do |sum, (rate, range)|
      start_at = [amount_already_taxed, range.begin - 1].max
      if start_at.to_f > range.end
        sum
      else
        end_at = [income + amount_already_taxed, range.end].min
        income_in_bracket = [end_at - start_at, 0].max
        pct = rate / 100.0
        sum + income_in_bracket * pct
      end
    end.round(2).to_f
  end

  def income_tax_brackets
    rates    = tax_brackets[:rates]
    brackets = tax_brackets[:brackets][filing_status].dup
    brackets << Float::INFINITY

    range_begin = 0
    rates.each.with_object Hash.new do |rate, h|
      range_end = brackets.shift
      h[rate] = (range_begin..range_end)
      range_begin = range_end + 1
    end
  end

  def itemized_deductions
    itemized_deductions_from_expenses + itemized_deductions_from_properties
  end

  def itemized_deductions_from_expenses
    Array(itemized_deductions_categories).inject 0 do |sum, (name, hash)|
      ary = expenses[name]
      if ary.blank?
        sum
      else
        monthly_expenses = ary.inject(0) { |sum, e| sum + e }.to_f
        floor = agi_floor hash.fetch('floor', 0)
        deduction = [(monthly_expenses * 12) - floor, 0].max
        sum + deduction
      end
    end
  end

  def itemized_deductions_from_properties
    return 0 if property.nil?
    taxes = property.appraised_value * (property.tax_rate / 100)
    interest = property.interest_paid_in_year(year)
    (taxes + interest).round 2
  end

  def incremental_medicare_ss(income, tax_form, amount_already_taxed)
    cfg = medicare_ss
    is_self_employed = tax_form.to_s == '1099'

    medicare = income * (cfg[:medicare] / 100.0)
    medicare *= 2 if is_self_employed

    if is_self_employed
      ss = income * (cfg[:ss] / 100.0) * 2
    else
      cap = [cfg[:ss_wage_base] - amount_already_taxed, 0].max
      amount_to_tax = [cap, income].min
      ss = amount_to_tax * (cfg[:ss] / 100.0)
    end

    [medicare, ss]
  end

  def net_income
    income_sources.inject 0 do |sum, is| sum + is.annual_net end
  end

  def standard_deduction
    standard_deductions[filing_status]
  end

  def deduction
    [itemized_deductions, standard_deduction].max
  end

  def exemption_total
    exemptions * exemption
  end

  def above_the_line_deductions
    from_hsa = Array(expenses[:hsa]).inject 0 do |sum, e|
      sum + (e * 12.0)
    end
    se_medicare_ss = income_sources.inject 0 do |sum, is|
      is_self_employed = is.tax_form.to_s == '1099'
      if is_self_employed
        cfg = medicare_ss
        gross_annual = is.annual_gross
        medicare = gross_annual * (cfg[:medicare] / 100.0)
        ss = gross_annual * (cfg[:ss] / 100.0)
        sum + medicare + ss
      else
        sum
      end
    end
    # FIXME: add student loan to scenario
  end

private

  module Year2000
    def self.extended(base)
      base.standard_deductions = {
        single: 4400,
      }

      base.tax_brackets = {
        rates: [15, 28],

        brackets: {
          single: [26250, 63550],
        },
      }

      base.medicare_ss = {
        medicare: 1.45,
        ss: 6.2,
        ss_wage_base: 76200,
      }

      base.exemption = 2800
    end
  end

  module Year2003
    def self.extended(base)
      base.standard_deductions = {
        married_filing_jointly: 9500,
      }

      base.tax_brackets = {
        rates: [10, 15],

        brackets: {
          married_filing_jointly: [14000, 45800],
        },
      }

      base.medicare_ss = {
        medicare: 1.45,
        ss: 6.2,
        ss_wage_base: 87000,
      }

      base.exemption = 3050
    end
  end

  module Year2005
    def self.extended(base)
      base.standard_deductions = {
        married_filing_jointly: 10000,
      }

      base.tax_brackets = {
        rates: [10, 15],

        brackets: {
          married_filing_jointly: [14600, 59400],
        },
      }

      base.medicare_ss = {
        medicare: 1.45,
        ss: 6.2,
        ss_wage_base: 90000,
      }

      base.exemption = 3200
    end
  end

  module Year2013
    def self.extended(base)
      base.standard_deductions = {
        single:                    6100,
        married_filing_jointly:    12200,
        married_filing_separately: 6100,
        head_of_household:         8950,
      }

      base.tax_brackets = {
        rates: [10, 15, 25, 28, 33, 35, 39.6],

        brackets: {
          single:                    [8925,  36250, 87850,  183250, 398350, 400000],
          married_filing_jointly:    [17850, 72500, 146400, 233050, 398350, 450000],
          married_filing_separately: [8925,  36250, 73200,  111525, 199175, 225000],
          head_of_household:         [12750, 48600, 125450, 203150, 398350, 425000],
        },
      }

      base.medicare_ss = {
        medicare: 1.45,
        ss: 6.2,
        ss_wage_base: 113700,
      }

      base.exemption = 3900
    end
  end
end
