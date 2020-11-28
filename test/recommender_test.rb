require_relative "test_helper"

class RecommenderTest < Minitest::Test
  def test_explicit
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    path = "#{Dir.mktmpdir}/recommender.bin"

    dump = Marshal.dump(recommender)
    File.binwrite(path, dump)

    dump = File.binread(path)
    recommender = Marshal.load(dump)

    assert_equal [1664, 20], recommender.item_factors.shape
    assert_equal [943, 20], recommender.user_factors.shape

    expected = data.map { |v| v[:rating] }.sum / data.size.to_f
    assert_in_delta expected, recommender.global_mean

    recs = recommender.item_recs("Star Wars (1977)")
    assert_equal 5, recs.size

    item_ids = recs.map { |r| r[:item_id] }
    assert_includes item_ids, "Empire Strikes Back, The (1980)"
    assert_includes item_ids, "Return of the Jedi (1983)"

    assert_in_delta 0.9972, recs.first[:score], 0.01
  end

  def test_implicit
    data = Disco.load_movielens
    data.each { |v| v.delete(:rating) }

    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    path = "#{Dir.mktmpdir}/recommender.bin"

    dump = Marshal.dump(recommender)
    File.binwrite(path, dump)

    dump = File.binread(path)
    recommender = Marshal.load(dump)

    assert_equal [1664, 20], recommender.item_factors.shape
    assert_equal [943, 20], recommender.user_factors.shape
    assert_equal 0, recommender.global_mean

    recs = recommender.item_recs("Star Wars (1977)", count: 10).map { |r| r[:item_id] }
    assert_includes recs, "Empire Strikes Back, The (1980)"
    assert_includes recs, "Return of the Jedi (1983)"
  end

  def test_examples
    recommender = Disco::Recommender.new
    recommender.fit([
      {user_id: 1, item_id: 1, rating: 5},
      {user_id: 2, item_id: 1, rating: 3}
    ])
    recommender.user_recs(1)
    recommender.item_recs(1)

    recommender = Disco::Recommender.new
    recommender.fit([
      {user_id: 1, item_id: 1, value: 1},
      {user_id: 2, item_id: 1, value: 2}
    ])
    recommender.user_recs(1)
    recommender.item_recs(1)
  end

  def test_rated
    data = [
      {user_id: 1, item_id: "A"},
      {user_id: 1, item_id: "B"},
      {user_id: 1, item_id: "C"},
      {user_id: 1, item_id: "D"},
      {user_id: 2, item_id: "C"},
      {user_id: 2, item_id: "D"},
      {user_id: 2, item_id: "E"},
      {user_id: 2, item_id: "F"}
    ]
    recommender = Disco::Recommender.new
    recommender.fit(data)
    assert_equal ["E", "F"], recommender.user_recs(1).map { |r| r[:item_id] }.sort
    assert_equal ["A", "B"], recommender.user_recs(2).map { |r| r[:item_id] }.sort
  end

  def test_validation_set_explicit
    data = Disco.load_movielens
    train_set = data.first(80000)
    validation_set = data.last(20000)
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(train_set, validation_set: validation_set)
  end

  def test_validation_set_implicit
    data = Disco.load_movielens
    data.each { |v| v.delete(:rating) }
    train_set = data.first(80000)
    validation_set = data.last(20000)
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(train_set, validation_set: validation_set)
  end

  def test_user_recs_item_ids
    recommender = Disco::Recommender.new
    recommender.fit([
      {user_id: 1, item_id: 1, rating: 5},
      {user_id: 1, item_id: 2, rating: 3}
    ])
    assert_equal [2], recommender.user_recs(1, item_ids: [2]).map { |r| r[:item_id] }
  end

  def test_user_recs_new_user
    recommender = Disco::Recommender.new
    recommender.fit([
      {user_id: 1, item_id: 1, rating: 5},
      {user_id: 2, item_id: 1, rating: 3}
    ])
    assert_empty recommender.user_recs(1000)
  end

  # TODO return global mean?
  def test_user_recs_new_item
    recommender = Disco::Recommender.new
    recommender.fit([
      {user_id: 1, item_id: 1, rating: 5},
      {user_id: 2, item_id: 1, rating: 3}
    ])
    assert_empty [], recommender.user_recs(1, item_ids: [1000])
  end

  # TODO better test
  def test_predict
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)
    recommender.predict(data.first(5))
  end

  def test_predict_user_recs_consistent
    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    expected = data.first(5).map { |v| recommender.user_recs(v[:user_id], item_ids: [v[:item_id]]).first[:score] }
    predictions = recommender.predict(data.first(5))
    5.times do |i|
      assert_in_delta expected[i], predictions[i]
    end
  end

  def test_no_training_data
    recommender = Disco::Recommender.new
    error = assert_raises ArgumentError do
      recommender.fit([])
    end
    assert_equal "No training data", error.message
  end

  def test_missing_user_id
    recommender = Disco::Recommender.new
    error = assert_raises ArgumentError do
      recommender.fit([{item_id: 1, rating: 5}])
    end
    assert_equal "Missing user_id", error.message
  end

  def test_missing_item_id
    recommender = Disco::Recommender.new
    error = assert_raises ArgumentError do
      recommender.fit([{user_id: 1, rating: 5}])
    end
    assert_equal "Missing item_id", error.message
  end

  def test_multiple_user_item
    skip # no error for now

    train_set = [
      {user_id: 1, item_id: 2, rating: 1},
      {user_id: 1, item_id: 2, rating: 2},
    ]
    recommender = Disco::Recommender.new
    error = assert_raises ArgumentError do
      recommender.fit(train_set)
    end
    assert_equal "Multiple observations for user 1, item 2", error.message
  end

  def test_not_fit
    recommender = Disco::Recommender.new
    error = assert_raises do
      recommender.user_recs(1)
    end
    assert_equal "Not fit", error.message
  end

  def test_rover
    movielens = Disco.load_movielens

    data =
      Rover::DataFrame.new({
        "user_id" => movielens.map { |v| v[:user_id] },
        "item_id" => movielens.map { |v| v[:item_id] },
        "rating" => movielens.map { |v| v[:rating] }
      })

    recommender = Disco::Recommender.new
    recommender.fit(data)

    # original data frame not modified
    assert_equal ["user_id", "item_id", "rating"], data.keys
  end

  def test_daru
    movielens = Disco.load_movielens

    data =
      Daru::DataFrame.new({
        "user_id" => movielens.map { |v| v[:user_id] },
        "item_id" => movielens.map { |v| v[:item_id] },
        "rating" => movielens.map { |v| v[:rating] }
      })

    recommender = Disco::Recommender.new
    recommender.fit(data)

    # original data frame not modified
    assert_equal ["user_id", "item_id", "rating"], data.vectors.to_a
  end

  def test_optimize_similar_items
    skip "NGT not available on Windows" if Gem.win_platform?

    data = Disco.load_movielens
    recommender = Disco::Recommender.new(factors: 20)
    recommender.fit(data)

    recommender.optimize_similar_items

    recs = recommender.item_recs("Star Wars (1977)")
    assert_equal 5, recs.size

    item_ids = recs.map { |r| r[:item_id] }
    assert_includes item_ids, "Empire Strikes Back, The (1980)"
    assert_includes item_ids, "Return of the Jedi (1983)"

    assert_in_delta 0.9972, recs.first[:score], 0.01
  end
end
