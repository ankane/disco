require_relative "test_helper"

class MetricsTest < Minitest::Test
  def test_rmse
    assert_in_delta 2, Disco::Metrics.rmse([0, 0, 0, 1, 1], [0, 2, 4, 1, 1])
  end
end
