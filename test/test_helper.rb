require "bundler/setup"
require "logger" # for Rails 7.0
require "active_record"
Bundler.require(:default)
require "minitest/autorun"

require_relative "support/active_record"
