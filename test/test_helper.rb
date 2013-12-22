require 'simplecov' if ENV['COVERAGE']

require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/reporters'

require 'ostruct'
require 'pp'

require 'mudrat_projector'

# Require pry library on demand to avoid eating its >500ms start up penalty
class Binding
  def method_missing sym, *args
    if sym == :pry && args.empty? && !block_given?
      require 'pry'
      pry
    else
      super
    end
  end
end

# Dates need friendlier output
class Date
  def inspect
    strftime
  end
end

# BigDecimal needs friendlier output
class BigDecimal < Numeric
  def inspect
    "#<BigDecmial:#{round(20).to_f.inspect}>"
  end
end

Minitest::Reporters.use! MiniTest::Reporters::DefaultReporter.new

class Minitest::Test
  include MudratProjector

  # Enable you to just call "jan_1_2000" to new up a date.
  def method_missing sym, *args, &block
    return super if block_given? || args.size > 0
    begin
      Date.parse sym.to_s
    rescue ArgumentError => ae
      super
    end
  end

  private

  def epoch
    jan_1_1970
  end

  def every_month **params
    end_date = params[:until]
    if end_date
      from = params[:from] || jan_1_2000
      count = DateDiff.date_diff unit: :month, from: from, to: end_date
      { unit: :month, scalar: 1, count: count }
    else
      { unit: :month, scalar: 1 }
    end
  end
end
