# frozen_string_literal: true

require 'elastic_manager/logger'

# Index closing operations
module Close
  include Logging

  def close_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, 'open', nil, @config)
    else
      if date_from.nil?
        result = @elastic.all_indices(date_from, date_to, daysago, 'open', nil, @config).select { |r| r.start_with?(*indices) }
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

  def do_close(indices)
    indices.each do |index|
      next if skip_index?(index, 'close')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already?(response, 'close')

        elastic_action_with_log('close_index', index, @config['settings']['box_types']['ingest'])
      else
        log.warn "#{index} index not found"
      end
    end
  end

  def close
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = close_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_close(indices)
  end
end
