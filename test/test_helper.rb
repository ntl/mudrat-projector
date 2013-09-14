require 'simplecov' if ENV['COVERAGE']

require 'minitest/autorun'
require 'minitest/reporters'

require 'ostruct'
require 'pry'

load File.expand_path('../../lib/load.rb', __FILE__)

MiniTest::Reporters.use! MiniTest::Reporters::DefaultReporter.new
