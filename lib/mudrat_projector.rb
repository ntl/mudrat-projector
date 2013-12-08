require "bigdecimal"
require "bigdecimal/util"
require "date"
require "forwardable"
require "yaml"

require "mudrat_projector/version"

module MudratProjector
  ABSOLUTE_START = Date.new 1970
  ABSOLUTE_END   = Date.new 9999

  def self.classify sym
    "_#{sym}".gsub %r{_[a-z]} do |bit|
      bit.slice! 0, 1
      bit.upcase!
      bit
    end
  end

  Dir.glob File.expand_path("../mudrat_projector/**/*.rb", __FILE__) do |path|
    base_without_ext =  File.basename path, ".*"
    klass_name       = classify base_without_ext
    relative_path    = File.join "mudrat_projector", base_without_ext
    autoload klass_name, relative_path
  end
end
