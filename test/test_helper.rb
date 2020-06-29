require "bundler/setup"
require "active_record"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "csv"
require "daru"
require "rover"

require_relative "support/active_record"
