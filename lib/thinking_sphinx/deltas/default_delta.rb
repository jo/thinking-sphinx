module ThinkingSphinx
  module Deltas
    class DefaultDelta
      attr_accessor :column

      def initialize(index, options)
        @index  = index
        @column = options.delete(:delta_column) || :delta
      end

      def index(model, instance = nil)
        return true unless ThinkingSphinx.updates_enabled? &&
          ThinkingSphinx.deltas_enabled?
        return true if instance && !toggled(instance)

        update_delta_indexes(model)
        delete_in_core_indexes(model, instance.sphinx_document_id) if instance

        true
      end

      def update_delta_indexes(model)
        config = ThinkingSphinx::Configuration.instance
        client = Riddle::Client.new config.address, config.port
        rotate = ThinkingSphinx.sphinx_running? ? "--rotate" : ""

        output = `#{config.bin_path}#{config.indexer_binary_name} --config #{config.config_file} #{rotate} #{delta_indexes(model)}`
        puts(output) unless ThinkingSphinx.suppress_delta_output?
      end

      def delete_in_core_indexes(model,document_id)
        model.sphinx_indexes.each do |index|
          model.delete_in_index("#{index.name}_core", document_id)
        end
      end

      def delta_indexes(model)
        model.sphinx_delta_indexes.collect { |i| "#{i.name}_delta"}.join(' ')
      end

      def core_indexes(model)
        model.sphinx_indexes.collect { |i| "#{i.name}_delta"}.join(' ')
      end

      def toggle(instance)
        instance.delta = true
      end

      def toggled(instance)
        instance.delta
      end

      def reset_query(model)
        "UPDATE #{model.quoted_table_name} SET " +
        "#{model.connection.quote_column_name(@column.to_s)} = #{adapter.boolean(false)} " +
        "WHERE #{model.connection.quote_column_name(@column.to_s)} = #{adapter.boolean(true)}"
      end

      def clause(model, toggled)
        "#{model.quoted_table_name}.#{model.connection.quote_column_name(@column.to_s)}" +
        " = #{adapter.boolean(toggled)}"
      end

      private

      def adapter
        @adapter = @index.model.sphinx_database_adapter
      end
    end
  end
end
