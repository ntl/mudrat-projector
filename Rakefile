require "rake/testtask"

ENV['COVERAGE'] = '1'

Rake::TestTask.new do |t|
  t.pattern = 'test/**/*_test.rb'
  t.libs << 'test'
end

desc "Update ctags"
task :ctags do
  `ctags -R --languages=Ruby --totals -f tags`
end

task :environment do
  $LOAD_PATH.push File.expand_path('../lib', __FILE__)
  require 'mudrat_projector'
end

desc "Open a pry console"
task :console => :environment do
  require 'pry'
  MudratProjector.pry
end

task default: :test
