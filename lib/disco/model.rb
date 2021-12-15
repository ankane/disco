module Disco
  module Model
    def has_recommended(name, class_name: nil)
      class_name ||= name.to_s.singularize.camelize

      class_eval do
        unless reflect_on_association(:recommendations)
          has_many :recommendations, class_name: "Disco::Recommendation", as: :subject, dependent: :destroy
        end

        has_many :"recommended_#{name}", -> { where("disco_recommendations.context = ?", name).order("disco_recommendations.score DESC") }, through: :recommendations, source: :item, source_type: class_name

        # TODO use fetch for item_id and score in 0.3.0
        define_method("update_recommended_#{name}") do |items|
          now = Time.now
          items = items.map { |item| {subject_type: model_name.name, subject_id: id, item_type: class_name, item_id: item[:item_id], context: name, score: item[:score], created_at: now, updated_at: now} }

          self.class.transaction do
            recommendations.where(context: name).delete_all

            if items.any?
              if recommendations.respond_to?(:insert_all!)
                # Rails 6
                recommendations.insert_all!(items)
              elsif recommendations.respond_to?(:bulk_import!)
                # activerecord-import
                recommendations.bulk_import!(items, validate: false)
              else
                recommendations.create!([items])
              end
            end
          end
        end
      end
    end
  end
end
