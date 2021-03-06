#
# Builds ActiveRecord migrations.
#
module ReflectiveRecord
  class MigrationBuilder

    def table_migration(table_name, attributes, drop_table=false)
      create_instruction = create_table_instruction table_name, attributes
      drop_instruction = drop_table_instruction table_name
      up_or_down_migration create_instruction, drop_instruction, drop_table
    end

    def column_migration(table_name, attribute_name, attribute_description, remove_column=false)
      add_instruction = add_column_instruction table_name, attribute_name, attribute_description
      remove_instruction = remove_column_instruction table_name, attribute_name, attribute_description
      up_or_down_migration add_instruction, remove_instruction, remove_column
    end

    def migrations_from_schema_variation(source_schema, target_schema, additions={}, removals={})
      migrations = []
      { true => removals, false => additions }.each do |reverse, changes|
        changes.each do |table_name, attributes|
          if source_schema[table_name] && !reverse or target_schema[table_name] && reverse
            attributes.each do |attribute_name, attribute_description|
              migrations << column_migration(table_name, attribute_name, attribute_description, reverse)
            end
          else
            unless ignore_migration_for?(table_name)
              migrations << table_migration(table_name, attributes, reverse)
            end
          end
        end
      end
      migrations
    end

    def migration_class_name(table_names=[], sequence_number=1)
      table_names.reject!{ |table_name| ignore_migration_for?(table_name) }
      table_names = table_names.map(&:to_s).map(&:camelize)
      if table_names.count > 2
        table_names = table_names[0..1] + ["More"]
      end
      prefix = table_names.count > 0 ? 'MigrationOf' : 'Migration'
      "#{prefix}#{table_names.join('And')}V#{'%03d' % sequence_number}"
    end

    def migration_class_definition(class_name, migrations=[])
      migration = "class #{class_name} < ActiveRecord::Migration\n"
      migration += up_instruction migrations
      migration += down_instruction migrations
      migration += "end\n"
    end

    def migration_file_name(table_names=[], sequence_number=1)
      migration_timestamp + '_' + migration_class_name(table_names, sequence_number).underscore + '.rb'
    end

    private

    def create_table_instruction(table_name, attributes)
      join_relations = ActiveRecord::Base.instance_variable_get :@reflective_joins
      table_option = join_relations.keys.include?(table_name) ? ', :id => false' : ''
      instruction = "    create_table :#{table_name}#{table_option} do |t|\n"
      attributes.each do |attribute_name, attribute_description|
        formatted_options = format_options attribute_description[:options]
        instruction += "      t.#{attribute_description[:type]} :#{attribute_name}#{formatted_options}\n"
      end
      instruction += "    end\n"
    end

    def drop_table_instruction(table_name)
      "    drop_table :#{table_name}\n"
    end

    def add_column_instruction(table_name, attribute_name, attribute_description)
      formatted_options = format_options attribute_description[:options]
      instruction = "    add_column :#{table_name}, :#{attribute_name}, :#{attribute_description[:type]}#{formatted_options}\n"
      # indexes_from_options(attribute_description[:options]).each do |index|
      #   instruction += add_index_instruction(table_name, index)
      # end
      instruction
    end

    def remove_column_instruction(table_name, attribute_name, attribute_description)
      instruction = "    remove_column :#{table_name}, :#{attribute_name}\n"
      # indexes_from_options(attribute_description[:options]).each do |index|
      #   instruction += remove_index_instruction(table_name, index)
      # end
      instruction
    end

    def add_index_instruction(table_name, index_definition)
      "    add_index :#{table_name}, #{index_definition.inspect}, :name => \"#{index_name(table_name, index_definition)}\"\n"
    end

    def remove_index_instruction(table_name, index_definition)
      "    remove_index :#{table_name}, :name => \"#{index_name(table_name, index_definition)}\"\n"
    end

    def index_name(table_name, index_definition)
      index_name = index_definition.to_s
      index_name = index_definition.join('_') if index_definition.respond_to?(:each)
      "#{table_name}_#{index_name}_index"
    end

    def up_instruction(migrations=[])
      instruction = "  def up\n"
      migrations.each{ |migration| instruction += migration[:up] }
      instruction += "  end\n\n"
    end

    def down_instruction(migrations=[])
      instruction = "  def down\n"
      migrations.each{ |migration| instruction += migration[:down] }
      instruction += "  end\n"
    end

    def up_or_down_migration(up_instruction, down_instruction, reverse_migration=false)
      if reverse_migration
        { up: down_instruction, down: up_instruction }
      else
        { up: up_instruction, down: down_instruction }
      end
    end

    def format_options(options)
      options_string = ""
      options.each { |option_name, option_value| options_string += ", :#{option_name} => #{option_value}" }
      options_string
    end

    def migration_timestamp
      @migration_timestamp ||= Time.now.strftime("%Y%m%d%H%M%S")
    end

    def ignore_migration_for?(table_name)
      @ignored_migrations ||= []
      ignore_migration = false
      if ActiveRecord::Base.respond_to?(:subclasses)
        #
        # Note:
        #   This condition makes sure that we ignore tables added by other gems.
        #   This is a relatively ugly hack. If we find a better way to do this,
        #   we should refactor this piece of code.
        #
        ignore_migration = (ActiveRecord::Base.subclasses.map(&:table_name).include?(table_name.to_s) ||
                             ActiveRecord::Base.subclasses.map(&:model_name).any?{ |model| model.constantize.reflect_on_all_associations.any?{ |association| association.plural_name == table_name.to_s } }) &&
                            !SchemaBuilder::ActiveRecord.new("#{Rails.root}/app/models").active_record_model_names.map(&:to_s).map(&:pluralize).include?(table_name.to_s)

        if ignore_migration && !@ignored_migrations.include?(table_name)
          puts "Ignoring #{table_name}"
          @ignored_migrations << table_name
        end
      end
      ignore_migration
    end

  end
end
