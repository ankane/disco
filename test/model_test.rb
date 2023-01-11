require_relative "test_helper"

class ModelTest < Minitest::Test
  def test_recommendations
    user = User.create!
    products = Product.create!([{name: "Product A"}, {name: "Product B"}].shuffle)
    user.update_recommended_products([
      {item_id: products.first.id, score: 1},
      {item_id: products.last.id, score: 0.5}
    ].shuffle)
    assert_equal products.size, user.recommendations.count
    assert_equal products, user.recommended_products.to_a
    assert_equal [], user.recommended_products_v2.to_a
  end

  def test_inheritance
    user = AdminUser.create!
    products = Product.create!([{name: "Product A"}, {name: "Product B"}].shuffle)
    user.update_recommended_products([
      {item_id: products.first.id, score: 1},
      {item_id: products.last.id, score: 0.5}
    ].shuffle)
    assert_equal products.size, user.recommendations.count
    assert_equal products, user.recommended_products.to_a
    assert_equal [], user.recommended_products_v2.to_a
  end
end
