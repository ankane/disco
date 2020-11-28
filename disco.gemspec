require_relative "lib/disco/version"

Gem::Specification.new do |spec|
  spec.name          = "disco"
  spec.version       = Disco::VERSION
  spec.summary       = "Recommendations for Ruby and Rails using collaborative filtering"
  spec.homepage      = "https://github.com/ankane/disco"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@chartkick.com"

  spec.files         = Dir["*.{md,txt}", "{app,lib}/**/*"]
  spec.require_path  = "lib"

  spec.required_ruby_version = ">= 2.4"

  spec.add_dependency "libmf", ">= 0.2.0"
  spec.add_dependency "numo-narray"
end
