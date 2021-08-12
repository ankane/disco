module Disco
  class Recommender
    attr_reader :global_mean

    def initialize(factors: 8, epochs: 20, verbose: nil, top_items: false)
      @factors = factors
      @epochs = epochs
      @verbose = verbose
      @user_map = {}
      @item_map = {}
      @top_items = top_items
    end

    def fit(train_set, validation_set: nil)
      train_set = to_dataset(train_set)
      validation_set = to_dataset(validation_set) if validation_set

      check_training_set(train_set)

      # TODO option to set in initializer to avoid pass
      # could also just check first few values
      # but may be confusing if they are all missing and later ones aren't
      @implicit = !train_set.any? { |v| v[:rating] }

      if @implicit && train_set.any? { |v| v[:value] }
        warn "[disco] WARNING: Passing `:value` with implicit feedback has no effect on recommendations and can be removed. Earlier versions of the library incorrectly stated this was used."
      end

      # TODO improve performance
      # (catch exception instead of checking ahead of time)
      unless @implicit
        check_ratings(train_set)

        if validation_set
          check_ratings(validation_set)
        end
      end

      @rated = Hash.new { |hash, key| hash[key] = {} }
      input = []
      train_set.each do |v|
        # update maps and build matrix in single pass
        u = (@user_map[v[:user_id]] ||= @user_map.size)
        i = (@item_map[v[:item_id]] ||= @item_map.size)
        @rated[u][i] = true

        # explicit will always have a value due to check_ratings
        input << [u, i, @implicit ? 1 : v[:rating]]
      end
      @rated.default = nil

      # much more efficient than checking every value in another pass
      raise ArgumentError, "Missing user_id" if @user_map.key?(nil)
      raise ArgumentError, "Missing item_id" if @item_map.key?(nil)

      # TODO improve performance
      unless @implicit
        @min_rating, @max_rating = train_set.minmax_by { |o| o[:rating] }.map { |o| o[:rating] }
      end

      if @top_items
        @item_count = [0] * @item_map.size
        @item_sum = [0.0] * @item_map.size
        train_set.each do |v|
          i = @item_map[v[:item_id]]
          @item_count[i] += 1
          @item_sum[i] += (@implicit ? 1 : v[:rating])
        end
      end

      eval_set = nil
      if validation_set
        eval_set = []
        validation_set.each do |v|
          u = @user_map[v[:user_id]]
          i = @item_map[v[:item_id]]

          # set to non-existent item
          u ||= -1
          i ||= -1

          eval_set << [u, i, @implicit ? 1 : v[:rating]]
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

      @normalized_user_factors = nil
      @normalized_item_factors = nil

      @user_recs_index = nil
      @similar_users_index = nil
      @similar_items_index = nil
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
        rated = item_ids ? {} : @rated[u]

        if item_ids
          ids = Numo::NArray.cast(item_ids.map { |i| @item_map[i] }.compact)
          return [] if ids.size == 0

          predictions = @item_factors[ids, true].inner(@user_factors[u, true])
          indexes = predictions.sort_index.reverse
          indexes = indexes[0...[count + rated.size, indexes.size].min] if count
          predictions = predictions[indexes]
          ids = ids[indexes]
        elsif @user_recs_index && count
          predictions, ids = @user_recs_index.search(@user_factors[u, true].expand_dims(0), count + rated.size).map { |v| v[0, true] }
        else
          predictions = @item_factors.inner(@user_factors[u, true])
          indexes = predictions.sort_index.reverse # reverse just creates view
          indexes = indexes[0...[count + rated.size, indexes.size].min] if count
          predictions = predictions[indexes]
          ids = indexes
        end

        predictions.inplace.clip(@min_rating, @max_rating) if @min_rating

        keys = @item_map.keys
        result = []
        ids.each_with_index do |item_id, i|
          next if rated[item_id]

          result << {item_id: keys[item_id], score: predictions[i]}
          break if result.size == count
        end
        result
      elsif @top_items
        top_items(count: count)
      else
        []
      end
    end

    def similar_items(item_id, count: 5)
      check_fit
      similar(item_id, @item_map, normalized_item_factors, count, @similar_items_index)
    end
    alias_method :item_recs, :similar_items

    def similar_users(user_id, count: 5)
      check_fit
      similar(user_id, @user_map, normalized_user_factors, count, @similar_users_index)
    end

    def top_items(count: 5)
      check_fit
      raise "top_items not computed" unless @top_items

      if @implicit
        scores = Numo::UInt64.cast(@item_count)
      else
        require "wilson_score"

        range = @min_rating..@max_rating
        scores = Numo::DFloat.cast(@item_sum.zip(@item_count).map { |s, c| WilsonScore.rating_lower_bound(s / c, c, range) })

        # TODO uncomment in 0.3.0
        # wilson score with continuity correction
        # https://en.wikipedia.org/wiki/Binomial_proportion_confidence_interval#Wilson_score_interval_with_continuity_correction
        # z = 1.96 # 95% confidence
        # range = @max_rating - @min_rating
        # n = Numo::DFloat.cast(@item_count)
        # phat = (Numo::DFloat.cast(@item_sum) - (@min_rating * n)) / range / n
        # phat = (phat - (1 / (2 * n))).clip(0, nil) # continuity correction
        # scores = (phat + z**2 / (2 * n) - z * Numo::DFloat::Math.sqrt((phat * (1 - phat) + z**2 / (4 * n)) / n)) / (1 + z**2 / n)
        # scores = scores * range + @min_rating
      end

      indexes = scores.sort_index.reverse
      indexes = indexes[0...[count, indexes.size].min] if count
      scores = scores[indexes]

      keys = @item_map.keys
      indexes.size.times.map do |i|
        {item_id: keys[indexes[i]], score: scores[i]}
      end
    end

    def user_ids
      @user_map.keys
    end

    def item_ids
      @item_map.keys
    end

    def user_factors(user_id = nil)
      if user_id
        u = @user_map[user_id]
        @user_factors[u, true] if u
      else
        @user_factors
      end
    end

    def item_factors(item_id = nil)
      if item_id
        i = @item_map[item_id]
        @item_factors[i, true] if i
      else
        @item_factors
      end
    end

    def optimize_user_recs
      check_fit
      @user_recs_index = create_index(item_factors, library: "faiss")
    end

    def optimize_similar_items(library: nil)
      check_fit
      @similar_items_index = create_index(normalized_item_factors, library: library)
    end
    alias_method :optimize_item_recs, :optimize_similar_items

    def optimize_similar_users(library: nil)
      check_fit
      @similar_users_index = create_index(normalized_user_factors, library: library)
    end

    def inspect
      to_s # for now
    end

    private

    # factors should already be normalized for similar users/items
    def create_index(factors, library:)
      # TODO make Faiss the default in 0.3.0
      library ||= defined?(Faiss) && !defined?(Ngt) ? "faiss" : "ngt"

      case library
      when "faiss"
        require "faiss"

        # inner product is cosine similarity with normalized vectors
        # https://github.com/facebookresearch/faiss/issues/95
        #
        # TODO use non-exact index in 0.3.0
        # https://github.com/facebookresearch/faiss/wiki/Faiss-indexes
        # index = Faiss::IndexHNSWFlat.new(factors.shape[1], 32, :inner_product)
        index = Faiss::IndexFlatIP.new(factors.shape[1])

        # ids are from 0...total
        # https://github.com/facebookresearch/faiss/blob/96b740abedffc8f67389f29c2a180913941534c6/faiss/Index.h#L89
        index.add(factors)

        index
      when "ngt"
        require "ngt"

        # could speed up search with normalized cosine
        # https://github.com/yahoojapan/NGT/issues/36
        index = Ngt::Index.new(factors.shape[1], distance_type: "Cosine")

        # NGT normalizes so could call create_index without normalized factors
        # but keep code simple for now
        ids = index.batch_insert(factors)
        raise "Unexpected ids. Please report a bug." if ids.first != 1 || ids.last != factors.shape[0]

        index
      else
        raise ArgumentError, "Invalid library: #{library}"
      end
    end

    def normalized_user_factors
      @normalized_user_factors ||= normalize(@user_factors)
    end

    def normalized_item_factors
      @normalized_item_factors ||= normalize(@item_factors)
    end

    def normalize(factors)
      norms = Numo::SFloat::Math.sqrt((factors * factors).sum(axis: 1))
      norms[norms.eq(0)] = 1e-10 # no zeros
      factors / norms.expand_dims(1)
    end

    def similar(id, map, norm_factors, count, index)
      i = map[id]

      if i && norm_factors.shape[0] > 1
        if index && count
          if defined?(Faiss) && index.is_a?(Faiss::Index)
            predictions, ids = index.search(norm_factors[i, true].expand_dims(0), count + 1).map { |v| v.to_a[0] }
          else
            result = index.search(norm_factors[i, true], size: count + 1)
            # ids from batch_insert start at 1 instead of 0
            ids = result.map { |v| v[:id] - 1 }
            # convert cosine distance to cosine similarity
            predictions = result.map { |v| 1 - v[:distance] }
          end
        else
          predictions = norm_factors.inner(norm_factors[i, true])
          indexes = predictions.sort_index.reverse
          indexes = indexes[0...[count + 1, indexes.size].min] if count
          predictions = predictions[indexes]
          ids = indexes
        end

        keys = map.keys

        # TODO use user_id for similar_users in 0.3.0
        key = :item_id

        result = []
        # items can have the same score
        # so original item may not be at index 0
        ids.each_with_index do |id, j|
          next if id == i

          result << {key => keys[id], score: predictions[j]}
        end
        result
      else
        []
      end
    end

    def check_ratings(ratings)
      unless ratings.all? { |r| !r[:rating].nil? }
        raise ArgumentError, "Missing rating"
      end
      unless ratings.all? { |r| r[:rating].is_a?(Numeric) }
        raise ArgumentError, "Rating must be numeric"
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
        item_factors: @item_factors,
        factors: @factors,
        epochs: @epochs,
        verbose: @verbose
      }

      unless @implicit
        obj[:min_rating] = @min_rating
        obj[:max_rating] = @max_rating
      end

      if @top_items
        obj[:item_count] = @item_count
        obj[:item_sum] = @item_sum
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
      @factors = obj[:factors]
      @epochs = obj[:epochs]
      @verbose = obj[:verbose]

      unless @implicit
        @min_rating = obj[:min_rating]
        @max_rating = obj[:max_rating]
      end

      @top_items = obj.key?(:item_count)
      if @top_items
        @item_count = obj[:item_count]
        @item_sum = obj[:item_sum]
      end
    end
  end
end
