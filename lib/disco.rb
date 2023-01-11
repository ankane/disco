# dependencies
require "libmf"
require "numo/narray"

# modules
require_relative "disco/data"
require_relative "disco/metrics"
require_relative "disco/recommender"
require_relative "disco/version"

# integrations
require_relative "disco/engine" if defined?(Rails)

module Disco
  class Error < StandardError; end

  extend Data
end

if defined?(ActiveSupport.on_load)
  ActiveSupport.on_load(:active_record) do
    require_relative "disco/model"
    extend Disco::Model
  end
end
