module Disco
  class Recommender
    attr_reader :global_mean, :item_factors, :user_factors

    def initialize(factors: 8, epochs: 20, verbose: nil)
      @factors = factors
      @epochs = epochs
      @verbose = verbose
      @user_map = {}
      @item_map = {}
    end

    def fit(train_set, validation_set: nil)
      train_set = to_dataset(train_set)
      validation_set = to_dataset(validation_set) if validation_set

      check_training_set(train_set)

      @implicit = !train_set.any? { |v| v[:rating] }
      unless @implicit
        check_ratings(train_set)
        @min_rating, @max_rating = train_set.minmax_by { |o| o[:rating] }.map { |o| o[:rating] }

        if validation_set
          check_ratings(validation_set)
        end
      end

      update_maps(train_set)

      @rated = Hash.new { |hash, key| hash[key] = {} }
      input = []
      value_key = @implicit ? :value : :rating
      train_set.each do |v|
        u = @user_map[v[:user_id]]
        i = @item_map[v[:item_id]]
        @rated[u][i] = true

        # explicit will always have a value due to check_ratings
        input << [u, i, v[value_key] || 1]
      end
      @rated.default = nil

      eval_set = nil
      if validation_set
        eval_set = []
        validation_set.each do |v|
          u = @user_map[v[:user_id]]
          i = @item_map[v[:item_id]]

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

    # generates a prediction even if a user has already rated the item
    def predict(data)
      data = to_dataset(data)

      u = data.map { |v| @user_map[v[:user_id]] }
      i = data.map { |v| @item_map[v[:item_id]] }

      new_index = data.each_index.select { |index| u[index].nil? || i[index].nil? }
      new_index.each do |j|
        u[j] = 0
        i[j] = 0
      end

      predictions = @user_factors[u, true].inner(@item_factors[i, true])
      predictions.inplace.clip(@min_rating, @max_rating) if @min_rating
      predictions[new_index] = @global_mean
      predictions.to_a
    end

    def user_recs(user_id, count: 5, item_ids: nil)
      check_fit
      u = @user_map[user_id]

      if u
        predictions = @item_factors.inner(@user_factors[u, true])

        predictions =
          @item_map.keys.zip(predictions).map do |item_id, pred|
            {item_id: item_id, score: pred}
          end

        if item_ids
          idx = item_ids.map { |i| @item_map[i] }.compact
          predictions = predictions.values_at(*idx)
        else
          @rated[u].keys.sort_by { |v| -v }.each do |i|
            predictions.delete_at(i)
          end
        end

        predictions.sort_by! { |pred| -pred[:score] } # already sorted by id
        predictions = predictions.first(count) if count && !item_ids

        # clamp *after* sorting
        # also, only needed for returned predictions
        if @min_rating
          predictions.each do |pred|
            pred[:score] = pred[:score].clamp(@min_rating, @max_rating)
          end
        end

        predictions
      else
        # no items if user is unknown
        # TODO maybe most popular items
        []
      end
    end

    def optimize_similar_items
      check_fit
      @item_index = create_index(@item_factors)
    end
    alias_method :optimize_item_recs, :optimize_similar_items

    def optimize_similar_users
      check_fit
      @user_index = create_index(@user_factors)
    end

    def similar_items(item_id, count: 5)
      check_fit
      similar(item_id, @item_map, @item_factors, @item_index ? nil : item_norms, count, @item_index)
    end
    alias_method :item_recs, :similar_items

    def similar_users(user_id, count: 5)
      check_fit
      similar(user_id, @user_map, @user_factors, @user_index ? nil : user_norms, count, @user_index)
    end

    private

    def create_index(factors)
      require "ngt"

      # could speed up search with normalized cosine
      # https://github.com/yahoojapan/NGT/issues/36
      index = Ngt::Index.new(factors.shape[1], distance_type: "Cosine")
      ids = index.batch_insert(factors)
      raise "Unexpected ids. Please report a bug." if ids.first != 1 || ids.last != factors.shape[0]
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
              item_id: keys[v[:id] - 1],
              # convert cosine distance to cosine similarity
              score: 1 - v[:distance]
            }
          end
        else
          # cosine similarity without norms[i]
          # otherwise, denominator would be (norms[i] * norms)
          predictions = factors.inner(factors[i, true]) / norms

          predictions =
            map.keys.zip(predictions).map do |item_id, pred|
              {item_id: item_id, score: pred}
            end

          max_score = predictions.delete_at(i)[:score]
          predictions.sort_by! { |pred| -pred[:score] } # already sorted by id
          predictions = predictions.first(count) if count
          # divide by norms[i] to get cosine similarity
          # only need to do for returned records
          predictions.each { |pred| pred[:score] /= norms[i] }
          predictions
        end
      else
        []
      end
    end

    def update_maps(train_set)
      raise ArgumentError, "Missing user_id" if train_set.any? { |v| v[:user_id].nil? }
      raise ArgumentError, "Missing item_id" if train_set.any? { |v| v[:item_id].nil? }

      train_set.each do |v|
        @user_map[v[:user_id]] ||= @user_map.size
        @item_map[v[:item_id]] ||= @item_map.size
      end
    end

    def check_ratings(ratings)
      unless ratings.all? { |r| !r[:rating].nil? }
        raise ArgumentError, "Missing ratings"
      end
      unless ratings.all? { |r| r[:rating].is_a?(Numeric) }
        raise ArgumentError, "Ratings must be numeric"
      end
    end

    def check_training_set(train_set)
      raise ArgumentError, "No training data" if train_set.empty?
    end

    def check_fit
      raise "Not fit" unless defined?(@implicit)
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
        user_map: @user_map,
        item_map: @item_map,
        rated: @rated,
        global_mean: @global_mean,
        user_factors: @user_factors,
        item_factors: @item_factors
      }

      unless @implicit
        obj[:min_rating] = @min_rating
        obj[:max_rating] = @max_rating
      end

      obj
    end

    def marshal_load(obj)
      @implicit = obj[:implicit]
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
