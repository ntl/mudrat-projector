require "rake/testtask"

ENV['COVERAGE'] = '1'

Rake::TestTask.new do |t|
  t.pattern = 'test/**/*_test.rb'
  t.libs << 'test'
end

task :ctags do
  `ctags -R --languages=Ruby --totals -f tags`
end

task default: :test
