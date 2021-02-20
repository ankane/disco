module Disco
  class Recommender
    attr_reader :global_mean

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

      result = []
      if u
        rated = item_ids ? {} : @rated[u]
        keys = @item_map.keys

        if item_ids
          ids = Numo::NArray.cast(item_ids.map { |i| @item_map[i] }.compact)
          return [] if ids.size == 0

          predictions = @item_factors[ids, true].inner(@user_factors[u, true])
          indexes = predictions.sort_index.reverse
          indexes = indexes[0...[count + rated.size, indexes.size].min] if count
          predictions = predictions[indexes]
          ids = ids[indexes]
        elsif @user_recs_index
          predictions, ids = @user_recs_index.search(@user_factors[u, true].expand_dims(0), count + rated.size).map { |v| v[0, true] }
        else
          predictions = @item_factors.inner(@user_factors[u, true])
          # TODO make sure reverse isn't hurting performance
          indexes = predictions.sort_index.reverse
          indexes = indexes[0...[count + rated.size, indexes.size].min] if count
          predictions = predictions[indexes]
          ids = indexes
        end

        predictions.inplace.clip(@min_rating, @max_rating) if @min_rating

        ids.each_with_index do |item_id, i|
          next if rated[item_id]

          result << {item_id: keys[item_id], score: predictions[i]}
          break if result.size == count
        end
      else
        # no items if user is unknown
        # TODO maybe most popular items
      end

      result
    end

    def optimize_user_recs
      check_fit

      require "faiss"

      # https://github.com/facebookresearch/faiss/wiki/Faiss-indexes
      # TODO use non-exact index
      @user_recs_index = Faiss::IndexFlatIP.new(item_factors.shape[1])

      # ids are from 0...total
      # https://github.com/facebookresearch/faiss/blob/96b740abedffc8f67389f29c2a180913941534c6/faiss/Index.h#L89
      @user_recs_index.add(item_factors)

      nil
    end

    def optimize_similar_items(library: nil)
      check_fit
      @similar_items_index = create_index(:item, library: library)
    end
    alias_method :optimize_item_recs, :optimize_similar_items

    def optimize_similar_users(library: nil)
      check_fit
      @similar_users_index = create_index(:user, library: library)
    end

    def similar_items(item_id, count: 5)
      check_fit
      similar(item_id, @item_map, @item_factors, @similar_items_index ? @item_norms : item_norms, count, @similar_items_index)
    end
    alias_method :item_recs, :similar_items

    def similar_users(user_id, count: 5)
      check_fit
      similar(user_id, @user_map, @user_factors, @similar_users_index ? @user_norms : user_norms, count, @similar_users_index)
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

    private

    def create_index(key, library:)
      # TODO make Faiss the default in 0.3.0
      library ||= defined?(Faiss) && !defined?(Ngt) ? "faiss" : "ngt"

      factors = send("#{key}_factors")

      case library
      when "faiss"
        require "faiss"

        # inner product is cosine similarity with normalized vectors
        # https://github.com/facebookresearch/faiss/issues/95
        index = Faiss::IndexFlatIP.new(factors.shape[1])
        index.add(factors / send("#{key}_norms").expand_dims(1))
        index
      when "ngt"
        require "ngt"

        # could speed up search with normalized cosine
        # https://github.com/yahoojapan/NGT/issues/36
        index = Ngt::Index.new(factors.shape[1], distance_type: "Cosine")
        ids = index.batch_insert(factors)
        raise "Unexpected ids. Please report a bug." if ids.first != 1 || ids.last != factors.shape[0]
        index
      else
        raise ArgumentError, "Invalid library: #{library}"
      end
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

      if i && factors.shape[0] > 1
        # TODO use user_id for similar_users in 0.3.0
        key = :item_id

        keys = map.keys

        if index && count
          if defined?(Faiss) && index.is_a?(Faiss::Index)
            distances, ids = index.search(factors[i, true].expand_dims(0) / norms[i], count + 1).map { |v| v.to_a[0] }
            ids.zip(distances).map do |id, distance|
              {key => keys[id], score: distance}
            end[1..-1]
          else
            result = index.search(factors[i, true], size: count + 1)[1..-1]
            result.map do |v|
              {
                # ids from batch_insert start at 1 instead of 0
                key => keys[v[:id] - 1],
                # convert cosine distance to cosine similarity
                score: 1 - v[:distance]
              }
            end
          end
        else
          predictions = factors.inner(factors[i, true] / norms[i]) / norms
          indexes = predictions.sort_index
          indexes = indexes[(-count - 1)..-2] if count
          indexes = indexes.reverse
          scores = predictions[indexes]

          indexes.size.times.map do |i|
            {key => keys[indexes[i]], score: scores[i]}
          end
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
