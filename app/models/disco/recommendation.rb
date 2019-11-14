module Disco
  class Recommendation < ActiveRecord::Base
    self.table_name = "disco_recommendations"

    belongs_to :subject, polymorphic: true
    belongs_to :item, polymorphic: true
  end
end
