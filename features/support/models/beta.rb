class Beta < ActiveRecord::Base
  define_index do
    indexes :name, :sortable => true
    has value

    set_property :delta => true
  end
  define_index do
    index_name 'alternative_beta'

    indexes :name, :sortable => true
    has value

    set_property :delta => true
  end
end
