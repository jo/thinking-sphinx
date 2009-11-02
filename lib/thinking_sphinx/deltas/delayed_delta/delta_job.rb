module ThinkingSphinx
  module Deltas
    class DeltaJob

      def initialize(model)
        @model = model
      end

      def perform
        return true unless ThinkingSphinx.updates_enabled? &&
          ThinkingSphinx.deltas_enabled?

        update_delta_indexes(model)

        true
      end
    end
  end
end
