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
