# dependencies
require "libmf"
require "numo/narray"

# stdlib
require "csv"
require "fileutils"
require "net/http"

# modules
require "disco/data"
require "disco/recommender"
require "disco/version"

# integrations
require "disco/engine" if defined?(Rails)

module Disco
  class Error < StandardError; end

  extend Data
end

if defined?(ActiveSupport.on_load)
  ActiveSupport.on_load(:active_record) do
    require "disco/model"
    extend Disco::Model
  end
end
