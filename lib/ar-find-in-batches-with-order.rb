require "ar-find-in-batches-with-order/version"

module ActiveRecord
  module FindInBatchesWithOrder
    def find_in_batches_with_order(options = {})
      relation = self

      # we have to be explicit about the options to ensure proper ordering and retrieval

      direction = options.delete(:direction) || (arel.orders.first.try(:ascending?) ? :asc : nil) || (arel.orders.first.try(:descending?) ? :desc : nil) || raise("please pass :direction that matches sort order")
      start = options.delete(:start)
      collate = options[:collate] ? "COLLATE #{connection.quote_column_name(options[:collate])}" : ""
      batch_size = options.delete(:batch_size) || 1000
      with_start_ids = []

      # try to deduct the property_key, but safer to specificy directly
      property_key = options.delete(:property_key) || arel.orders.first.try(:value).try(:name) || arel.orders.first.try(:split,' ').try(:first)
      tbl = connection.quote_table_name(options.delete(:property_table_name) || table.name)
      sanitized_key = "#{tbl}.#{connection.quote_column_name(property_key)}"
      # handle nested values for Rails < 6.0.3 versions that don't allow you to add attributes from joined tables when using includes
      # https://github.com/rails/rails/issues/34889
      parent_key = options.delete(:parent_key)
      relation = relation.limit(batch_size)

      records = start ? (direction == :desc ? relation.where("#{sanitized_key} <= ?", start).to_a : relation.where("#{sanitized_key} >= ?", start).to_a)  : relation.to_a

      while records.any?
        records_size = records.size

        yield records


        break if records_size < batch_size

        next_start = get_property_val(records.last, parent_key, property_key)
        with_start_ids.clear if start != next_start
        start = next_start

        records.each do |record|
          if get_property_val(record, parent_key, property_key) == start
            with_start_ids << record.id
          end
        end

        without_dups = relation.where.not(relation.klass.primary_key => with_start_ids)
        records = (direction == :desc ? without_dups.where("#{sanitized_key} <= ? #{collate}", start).to_a : without_dups.where("#{sanitized_key} >= ? #{collate}", start).to_a)
      end
    end

    def find_each_with_order(options = {})
      find_in_batches_with_order(options) do |records|

        records.each do |record|
          yield record
        end
      end
    end

    def get_property_val(record, parent_key, property_key)
      parent_key ? record.send(parent_key).send(property_key) : record.send(property_key)
    end
  end

  class Relation
    include FindInBatchesWithOrder
  end
end
