# frozen_string_literal: true

require 'elastic_manager/logger'

# Index deleting operations
module Delete
  include Logging

  def delete_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, nil, nil, @config)
    else
      if date_from.nil?
        result = @elastic.all_indices(date_from, date_to, daysago, nil, nil, @config).select { |r| r.start_with?(*indices) }
      else
        date_from.upto(date_to) do |date|
          indices.each do |index|
            date_formatted = date.to_s.tr('-', '.')
            result << "#{index}-#{date_formatted}"
          end
        end
      end
    end

    return result unless result.empty?

    log.fatal 'no indices for work'
    exit 1
  end

  def do_delete(indices)
    indices.each do |index|
      next if skip_index?(index, 'delete')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)

        elastic_action_with_log('delete_index', index, delete_without_snapshot?(index))
      else
        log.warn "#{index} index not found"
      end
    end
  end

  def delete
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = delete_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_delete(indices)
  end
end
