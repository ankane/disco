module Disco
  module Data
    def load_movielens
      item_path = download_file("ml-100k/u.item", "https://files.grouplens.org/datasets/movielens/ml-100k/u.item",
        file_hash: "553841ebc7de3a0fd0d6b62a204ea30c1e651aacfb2814c7a6584ac52f2c5701")
      data_path = download_file("ml-100k/u.data", "https://files.grouplens.org/datasets/movielens/ml-100k/u.data",
        file_hash: "06416e597f82b7342361e41163890c81036900f418ad91315590814211dca490")

      movies = {}
      File.foreach(item_path) do |line|
        row = line.encode("UTF-8", "ISO-8859-1").split("|")
        movies[row[0]] = row[1]
      end

      data = []
      File.foreach(data_path) do |line|
        row = line.split("\t")
        data << {
          user_id: row[0].to_i,
          item_id: movies[row[1]],
          rating: row[2].to_i
        }
      end

      data
    end

    private

    def download_file(fname, origin, file_hash:)
      require "digest"
      require "fileutils"
      require "open-uri"
      require "tmpdir"

      cache_home = ENV["XDG_CACHE_HOME"] || "#{ENV.fetch("HOME")}/.cache"
      dest = "#{cache_home}/disco/#{fname}"
      FileUtils.mkdir_p(File.dirname(dest))

      return dest if File.exist?(dest)

      Dir.mktmpdir do |dir|
        temp_path = "#{dir}/disco"

        puts "Downloading data from #{origin}"
        IO.copy_stream(URI.parse(origin).open(redirect: false), temp_path)

        digest = Digest::SHA256.file(temp_path)
        if digest.hexdigest != file_hash
          raise Error, "Bad hash: #{digest.hexdigest}"
        end
        puts "Hash verified: #{file_hash}"

        FileUtils.mv(temp_path, dest)
      end

      dest
    end
  end
end
