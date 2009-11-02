require 'thinking_sphinx/active_record/attribute_updates'
require 'thinking_sphinx/active_record/delta'
require 'thinking_sphinx/active_record/has_many_association'
require 'thinking_sphinx/active_record/scopes'

module ThinkingSphinx
  # Core additions to ActiveRecord models - define_index for creating indexes
  # for models. If you want to interrogate the index objects created for the
  # model, you can use the class-level accessor :sphinx_indexes.
  #
  module ActiveRecord
    def self.included(base)
      base.class_eval do
        class_inheritable_array :sphinx_indexes, :sphinx_facets
        class << self

          def set_sphinx_primary_key(attribute)
            @sphinx_primary_key_attribute = attribute
          end

          def primary_key_for_sphinx
            @sphinx_primary_key_attribute || primary_key
          end

          # Allows creation of indexes for Sphinx. If you don't do this, there
          # isn't much point trying to search (or using this plugin at all,
          # really).
          #
          # An example or two:
          #
          #   define_index
          #     indexes :id, :as => :model_id
          #     indexes name
          #   end
          #
          # You can also grab fields from associations - multiple levels deep
          # if necessary.
          #
          #   define_index do
          #     indexes tags.name, :as => :tag
          #     indexes articles.content
          #     indexes orders.line_items.product.name, :as => :product
          #   end
          #
          # And it will automatically concatenate multiple fields:
          #
          #   define_index do
          #     indexes [author.first_name, author.last_name], :as => :author
          #   end
          #
          # The #indexes method is for fields - if you want attributes, use
          # #has instead. All the same rules apply - but keep in mind that
          # attributes are for sorting, grouping and filtering, not searching.
          #
          #   define_index do
          #     # fields ...
          #
          #     has created_at, updated_at
          #   end
          #
          # One last feature is the delta index. This requires the model to
          # have a boolean field named 'delta', and is enabled as follows:
          #
          #   define_index do
          #     # fields ...
          #     # attributes ...
          #
          #     set_property :delta => true
          #   end
          #
          # Check out the more detailed documentation for each of these methods
          # at ThinkingSphinx::Index::Builder.
          #
          def define_index(&block)
            return unless ThinkingSphinx.define_indexes?

            self.sphinx_indexes ||= []
            self.sphinx_facets  ||= []

            delta_index_exists = sphinx_indexes.any? { |i| i.delta? }

            index = ThinkingSphinx::Index::Builder.generate(self, &block)

            self.sphinx_indexes << index
            unless ThinkingSphinx.indexed_models.include?(self.name)
              ThinkingSphinx.indexed_models << self.name
            end

            # Add delta Hooks just once
            if index.delta? && !delta_index_exists
              before_save   :toggle_delta
              after_commit  :index_delta
            end

            # add deleted hook and includes just once
            if sphinx_indexes.length == 1

              after_destroy :toggle_deleted

              include ThinkingSphinx::SearchMethods
              include ThinkingSphinx::ActiveRecord::AttributeUpdates
              include ThinkingSphinx::ActiveRecord::Scopes
            end

            index

            # We want to make sure that if the database doesn't exist, then Thinking
            # Sphinx doesn't mind when running non-TS tasks (like db:create, db:drop
            # and db:migrate). It's a bit hacky, but I can't think of a better way.
          rescue StandardError => err
            case err.class.name
            when "Mysql::Error", "Java::JavaSql::SQLException", "ActiveRecord::StatementInvalid"
              return
            else
              raise err
            end
          end
          alias_method :sphinx_index, :define_index

          def sphinx_index_options
            sphinx_indexes.last.options
          end

          # Generate a unique CRC value for the model's name, to use to
          # determine which Sphinx documents belong to which AR records.
          #
          # Really only written for internal use - but hey, if it's useful to
          # you in some other way, awesome.
          #
          def to_crc32
            self.name.to_crc32
          end

          def to_crc32s
            (subclasses << self).collect { |klass| klass.to_crc32 }
          end

          def source_of_sphinx_index
            possible_models = self.sphinx_indexes.collect { |index| index.model }
            return self if possible_models.include?(self)

            parent = self.superclass
            while !possible_models.include?(parent) && parent != ::ActiveRecord::Base
              parent = parent.superclass
            end

            return parent
          end

          def to_riddle(offset)
            sphinx_database_adapter.setup

            sphinx_indexes.select do |ts_index|
              ts_index.model == self
            end.inject([]) do |indexes,ts_index|
              indexes += ts_index.to_riddle(offset)
            end
          end

          def sphinx_database_adapter
            @sphinx_database_adapter ||=
              ThinkingSphinx::AbstractAdapter.detect(self)
          end

          def sphinx_name
            self.name.underscore.tr(':/\\', '_')
          end

          def sphinx_index_names
            sphinx_indexes.inject([]) do |names,ts_index|
              names += ts_index.all_index_names
            end
          end

          def sphinx_delta_indexes
            sphinx_indexes.select{|i| i.delta?}
          end

          def delete_in_index(index_name, document_id)
            return unless in_index?(index_name,document_id)
            config = ThinkingSphinx::Configuration.instance
            client = Riddle::Client.new config.address, config.port

            client.update(index_name,
                          ['sphinx_deleted'],
                          {document_id => 1}
                          )

          end

          def in_index?(index_name,document_id)
            search_for_id(document_id, index_name)
          end

        end
      end

      base.send(:include, ThinkingSphinx::ActiveRecord::Delta)

      ::ActiveRecord::Associations::HasManyAssociation.send(
        :include, ThinkingSphinx::ActiveRecord::HasManyAssociation
      )
      ::ActiveRecord::Associations::HasManyThroughAssociation.send(
        :include, ThinkingSphinx::ActiveRecord::HasManyAssociation
      )
    end

    def toggle_deleted
      return unless ThinkingSphinx.updates_enabled? && ThinkingSphinx.sphinx_running?

      self.class.sphinx_indexes.each do |index|
        delete_in_index("#{index.name}_core")
        delete_in_index("#{index.name}_delta") if index.delta?
      end
    rescue ::ThinkingSphinx::ConnectionError
      # nothing
    end

    def delete_in_index(index_name)
      self.class.delete_in_index(index_name,sphinx_document_id)
    end

    # Returns the unique integer id for the object. This method uses the
    # attribute hash to get around ActiveRecord always mapping the #id method
    # to whatever the real primary key is (which may be a unique string hash).
    #
    # @return [Integer] Unique record id for the purposes of Sphinx.
    #
    def primary_key_for_sphinx
      @primary_key_for_sphinx ||= read_attribute(self.class.primary_key_for_sphinx)
    end

    def sphinx_document_id
      primary_key_for_sphinx * ThinkingSphinx.indexed_models.size +
        ThinkingSphinx.indexed_models.index(self.class.source_of_sphinx_index.name)
    end

  end
end
