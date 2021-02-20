module Disco
  module Metrics
    class << self
      def rmse(act, exp)
        raise ArgumentError, "Size mismatch" if act.size != exp.size
        Math.sqrt(act.zip(exp).sum { |a, e| (a - e)**2 } / act.size.to_f)
      end
    end
  end
end
