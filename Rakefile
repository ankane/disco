require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.pattern = "test/**/*_test.rb"
  t.warning = false # for daru
end

task default: :test

# TODO use benchmark-ips
def benchmark_user_recs(name, recommender)
  ms = Benchmark.realtime do
    recommender.user_ids.each do |user_id|
      recommender.user_recs(user_id)
    end
  end
  puts "%-8s %f" % [name, ms]
end

# TODO use benchmark-ips
def benchmark_item_recs(name, recommender)
  ms = Benchmark.realtime do
    recommender.item_ids.each do |item_id|
      recommender.item_recs(item_id)
    end
  end
  puts "%-8s %f" % [name, ms]
end

namespace :benchmark do
  task :user_recs do
    require "bundler/setup"
    Bundler.require
    require "benchmark"

    data = Disco.load_movielens
    recommender = Disco::Recommender.new
    recommender.fit(data)

    benchmark_user_recs("none", recommender)
    recommender.optimize_user_recs
    benchmark_user_recs("faiss", recommender)
  end

  task :item_recs do
    require "bundler/setup"
    Bundler.require
    require "benchmark"

    data = Disco.load_movielens
    recommender = Disco::Recommender.new
    recommender.fit(data)

    benchmark_item_recs("none", recommender)
    recommender.optimize_item_recs(library: "ngt")
    benchmark_item_recs("ngt", recommender)
    recommender.optimize_item_recs(library: "faiss")
    benchmark_item_recs("faiss", recommender)
  end
end
