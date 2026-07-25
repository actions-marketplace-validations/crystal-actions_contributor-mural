require "spec"
require "../src/hall_of_fame"

module SpecHelper
  FIXTURES = Path[__DIR__] / "fixtures"

  def self.fixture(*parts : String) : String
    (FIXTURES / Path[*parts]).to_s
  end
end
