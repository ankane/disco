module Disco
  class Recommender
    attr_reader :global_mean, :item_factors, :user_factors

    def initialize(factors: 8, epochs: 20, verbose: nil, user_key: :user_id, item_key: :item_id, value_key: nil, implicit: nil)
      @factors = factors
      @epochs = epochs
      @verbose = verbose
      @user_key = user_key
      @item_key = item_key
      @value_key = value_key
      @implicit = implicit
    end

    def fit(train_set, validation_set: nil)
      train_set = to_dataset(train_set)
      validation_set = to_dataset(validation_set) if validation_set

      # NOTE: use user-provided implicit flag or derive from train-set
      @implicit = !train_set.any? { |v| v[:rating] } if @implicit.nil?

      unless @implicit
        ratings = train_set.map { |o| o[value_key] }
        check_ratings(ratings)
        @min_rating = ratings.min
        @max_rating = ratings.max

        if validation_set
          check_ratings(validation_set.map { |o| o[value_key] })
        end
      end

      check_training_set(train_set)
      create_maps(train_set)

      @rated = Hash.new { |hash, key| hash[key] = {} }
      input = []
      train_set.each do |v|
        u = @user_map[v[@user_key]]
        i = @item_map[v[@item_key]]
        @rated[u][i] = true

        # explicit will always have a value due to check_ratings
        input << [u, i, v[value_key] || 1]
      end
      @rated.default = nil

      eval_set = nil
      if validation_set
        eval_set = []
        validation_set.each do |v|
          u = @user_map[v[@user_key]]
          i = @item_map[v[@item_key]]

          # set to non-existent item
          u ||= -1
          i ||= -1

          eval_set << [u, i, v[value_key] || 1]
        end
      end

      loss = @implicit ? 12 : 0
      verbose = @verbose
      verbose = true if verbose.nil? && eval_set
      model = Libmf::Model.new(loss: loss, factors: @factors, iterations: @epochs, quiet: !verbose)
      model.fit(input, eval_set: eval_set)

      @global_mean = model.bias

      @user_factors = model.p_factors(format: :numo)
      @item_factors = model.q_factors(format: :numo)

      @user_index = nil
      @item_index = nil
    end

    def user_recs(user_id, count: 5, item_ids: nil)
      u = @user_map[user_id]

      if u
        predictions = @global_mean + @item_factors.dot(@user_factors[u, true])
        predictions.inplace.clip(@min_rating, @max_rating) if @min_rating

        predictions =
          @item_map.keys.zip(predictions).map do |item_id, pred|
            {@item_key => item_id, score: pred}
          end

        if item_ids
          idx = item_ids.map { |i| @item_map[i] }.compact
          predictions.values_at(*idx)
        else
          @rated[u].keys.each do |i|
            predictions.delete_at(i)
          end
        end

        predictions.sort_by! { |pred| -pred[:score] } # already sorted by id
        predictions = predictions.first(count) if count && !item_ids
        predictions
      else
        # no items if user is unknown
        # TODO maybe most popular items
        []
      end
    end

    def optimize_similar_items
      @item_index = create_index(@item_factors)
    end
    alias_method :optimize_item_recs, :optimize_similar_items

    def optimize_similar_users
      @user_index = create_index(@user_factors)
    end

    def similar_items(item_id, count: 5)
      similar(item_id, @item_map, @item_factors, item_norms, count, @item_index)
    end
    alias_method :item_recs, :similar_items

    def similar_users(user_id, count: 5)
      similar(user_id, @user_map, @user_factors, user_norms, count, @user_index)
    end

    private

    # NOTE: use user-provided value key, or derive key from mode
    def value_key
      @value_key ||= @implicit ? :value : :rating
    end

    def create_index(factors)
      require "ngt"

      index = Ngt::Index.new(factors.shape[1], distance_type: "Cosine")
      index.batch_insert(factors)
      index
    end

    def user_norms
      @user_norms ||= norms(@user_factors)
    end

    def item_norms
      @item_norms ||= norms(@item_factors)
    end

    def norms(factors)
      norms = Numo::SFloat::Math.sqrt((factors * factors).sum(axis: 1))
      norms[norms.eq(0)] = 1e-10 # no zeros
      norms
    end

    def similar(id, map, factors, norms, count, index)
      i = map[id]
      if i
        if index && count
          keys = map.keys
          result = index.search(factors[i, true], size: count + 1)[1..-1]
          result.map do |v|
            {
              # ids from batch_insert start at 1 instead of 0
              @item_key => keys[v[:id] - 1],
              # convert cosine distance to cosine similarity
              score: 1 - v[:distance]
            }
          end
        else
          predictions = factors.dot(factors[i, true]) / norms

          predictions =
            map.keys.zip(predictions).map do |item_id, pred|
              {@item_key => item_id, score: pred}
            end

          max_score = predictions.delete_at(i)[:score]
          predictions.sort_by! { |pred| -pred[:score] } # already sorted by id
          predictions = predictions.first(count) if count
          # divide by max score to get cosine similarity
          # only need to do for returned records
          predictions.each { |pred| pred[:score] /= max_score }
          predictions
        end
      else
        []
      end
    end

    def create_maps(train_set)
      user_ids = train_set.map { |v| v[@user_key] }.uniq.sort
      item_ids = train_set.map { |v| v[@item_key] }.uniq.sort

      raise ArgumentError, "Missing #{@user_key}" if user_ids.any?(&:nil?)
      raise ArgumentError, "Missing #{@item_key}" if item_ids.any?(&:nil?)

      @user_map = user_ids.zip(user_ids.size.times).to_h
      @item_map = item_ids.zip(item_ids.size.times).to_h
    end

    def check_ratings(ratings)
      unless ratings.all? { |r| !r.nil? }
        raise ArgumentError, "Missing ratings"
      end
      unless ratings.all? { |r| r.is_a?(Numeric) }
        raise ArgumentError, "Ratings must be numeric"
      end
    end

    def check_training_set(train_set)
      raise ArgumentError, "No training data" if train_set.empty?
    end

    def to_dataset(dataset)
      if defined?(Rover::DataFrame) && dataset.is_a?(Rover::DataFrame)
        # convert keys to symbols
        dataset = dataset.dup
        dataset.keys.each do |k, v|
          dataset[k.to_sym] ||= dataset.delete(k)
        end
        dataset.to_a
      elsif defined?(Daru::DataFrame) && dataset.is_a?(Daru::DataFrame)
        # convert keys to symbols
        dataset = dataset.dup
        new_names = dataset.vectors.to_a.map { |k| [k, k.to_sym] }.to_h
        dataset.rename_vectors!(new_names)
        dataset.to_a[0]
      else
        dataset
      end
    end

    def marshal_dump
      obj = {
        implicit: @implicit,
        user_key: @user_key,
        item_key: @item_key,
        value_key: @value_key,
        user_map: @user_map,
        item_map: @item_map,
        rated: @rated,
        global_mean: @global_mean,
        user_factors: @user_factors,
        item_factors: @item_factors,
      }

      unless @implicit
        obj[:min_rating] = @min_rating
        obj[:max_rating] = @max_rating
      end

      obj
    end

    def marshal_load(obj)
      @implicit = obj[:implicit]
      @user_key = obj[:user_key]
      @item_key = obj[:item_key]
      @value_key = obj[:value_key]
      @user_map = obj[:user_map]
      @item_map = obj[:item_map]
      @rated = obj[:rated]
      @global_mean = obj[:global_mean]
      @user_factors = obj[:user_factors]
      @item_factors = obj[:item_factors]

      unless @implicit
        @min_rating = obj[:min_rating]
        @max_rating = obj[:max_rating]
      end
    end
  end
end
