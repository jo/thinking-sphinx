module ThinkingSphinx
  module Deltas
    class FlagAsDeletedJob

      def initialize(model, instance)
        @model, @document_id = model, instance.sphinx_document_id
      end

      def perform
        return true unless ThinkingSphinx.updates_enabled?

        delete_in_core_indexes(@model, @document_id)

        true
      end
    end
  end
end
