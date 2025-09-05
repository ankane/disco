require "bundler/setup"
require "logger" # for Rails 7.0
require "active_record"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "daru"
require "rover"

require_relative "support/active_record"
