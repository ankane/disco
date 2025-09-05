require_relative "test_helper"

class OptimizeTest < Minitest::Test
  def setup
    skip "Not available on Windows" if windows?
    super
  end

  def test_optimize_user_recs
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    original_recs = recommender.user_recs(1)

    recommender.optimize_user_recs

    recs = recommender.user_recs(1)
    assert_equal original_recs.map { |v| v[:item_id] }, recs.map { |v| v[:item_id] }
    original_recs.zip(recs).each do |exp, act|
      assert_in_delta exp[:score], act[:score]
    end
    assert_equal 5, recs.size
  end

  def test_optimize_item_recs
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    original_recs = recommender.item_recs("Star Wars (1977)")

    recommender.optimize_item_recs(library: "faiss")

    recs = recommender.item_recs("Star Wars (1977)")
    assert_equal original_recs.map { |v| v[:item_id] }, recs.map { |v| v[:item_id] }
    original_recs.zip(recs).each do |exp, act|
      assert_in_delta exp[:score], act[:score]
    end
    assert_equal 5, recs.size

    item_ids = recs.map { |r| r[:item_id] }
    assert_includes item_ids, "Empire Strikes Back, The (1980)"
    assert_includes item_ids, "Return of the Jedi (1983)"

    assert_in_delta 0.9972, recs.first[:score], 0.01
  end

  def test_optimize_similar_users
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    original_recs = recommender.similar_users(1)

    recommender.optimize_similar_users(library: "faiss")

    recs = recommender.similar_users(1)

    assert_equal original_recs.map { |v| v[:user_id] }, recs.map { |v| v[:user_id] }
    original_recs.zip(recs).each do |exp, act|
      assert_in_delta exp[:score], act[:score]
    end
    assert_equal 5, recs.size
  end

  def test_optimize_item_recs_ngt
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    original_recs = recommender.item_recs("Star Wars (1977)")

    recommender.optimize_item_recs(library: "ngt")

    recs = recommender.item_recs("Star Wars (1977)")
    assert_equal original_recs.map { |v| v[:item_id] }, recs.map { |v| v[:item_id] }
    original_recs.zip(recs).each do |exp, act|
      assert_in_delta exp[:score], act[:score]
    end
    assert_equal 5, recs.size

    item_ids = recs.map { |r| r[:item_id] }
    assert_includes item_ids, "Empire Strikes Back, The (1980)"
    assert_includes item_ids, "Return of the Jedi (1983)"

    assert_in_delta 0.9972, recs.first[:score], 0.01
  end

  def test_optimize_similar_users_ngt
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    original_recs = recommender.similar_users(1, count: 10)

    recommender.optimize_similar_users(library: "ngt")

    recs = recommender.similar_users(1, count: 10)

    # won't match exactly due to ANN
    matching_ids = original_recs.map { |v| v[:user_id] } & recs.map { |v| v[:user_id] }
    assert_includes 8..10, matching_ids.size
    matching_ids.each do |user_id|
      exp = original_recs.find { |v| v[:user_id] == user_id }
      act = recs.find { |v| v[:user_id] == user_id }
      assert_in_delta exp[:score], act[:score]
    end
    assert_equal 10, recs.size
  end

  def windows?
    Gem.win_platform?
  end
end
