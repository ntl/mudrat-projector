class TaxCalculator
  attr :household, :projector

  def initialize projector: nil, household: nil
    @household = household
    @projector = projector
  end

  def project
    gross = 70000
    taxes = 19583.19

    OpenStruct.new(
      effective_rate: ((taxes * 100) / gross).round(2),
      gross:          gross,
      net:            gross - taxes,
      taxes:          taxes,
      year:           2013,
    )
  end

  Household = Struct.new :filing_status, :exemptions
end
