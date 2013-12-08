# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mudrat_projector/version'

Gem::Specification.new do |spec|
  spec.name          = "mudrat_projector"
  spec.version       = MudratProjector::VERSION
  spec.authors       = ["ntl"]
  spec.email         = ["nathanladd+github@gmail.com"]
  spec.description   = %q{Mudrat Projector is a simple financial projection engine.}
  spec.summary       = %q{Mudrat Projector is a simple financial projection engine designed for personal finance computations.}
  spec.homepage      = "https://github.com/ntl/mudrat-projector"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^test/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "minitest-reporters"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "timecop"
end
