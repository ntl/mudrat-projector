require 'simplecov' if ENV['COVERAGE']

require 'minitest/autorun'
require 'minitest/reporters'

require 'ostruct'
require 'pp'

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

load File.expand_path('../../lib/load.rb', __FILE__)

MiniTest::Reporters.use! MiniTest::Reporters::DefaultReporter.new

MiniTest::Unit::TestCase.class_eval do
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

  def every_month _end = nil
    {
      end:    _end,
      number: 1,
      type:   :recurring,
      unit:   :month,
    }
  end
end
