logger = ActiveSupport::Logger.new(ENV["VERBOSE"] ? STDOUT : nil)

# for debugging
ActiveRecord::Base.logger = logger

# migrations
ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

ActiveRecord::Migration.create_table :users do |t|
  t.string :name
end

ActiveRecord::Migration.create_table :products do |t|
  t.string :name
end

ActiveRecord::Migration.create_table :disco_recommendations do |t|
  t.references :subject, polymorphic: true
  t.references :item, polymorphic: true
  t.float :score
  t.string :context
  t.timestamps
end

class User < ActiveRecord::Base
  has_recommended :products
  has_recommended :products_v2, class_name: "Product"
end

class Product < ActiveRecord::Base
end

require_relative "../../app/models/disco/recommendation"
