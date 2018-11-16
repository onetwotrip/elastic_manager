# frozen_string_literal: true

require 'elastic_manager/logger'

# Index snapshoting operations
module Snapshot
  include Logging

  def snapshot_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, nil, @config['settings']['box_types']['store'], @config['settings']['indices'])
    else
      if date_from.nil?
        result = @elastic.all_indices(date_from, date_to, daysago, nil, @config['settings']['box_types']['store'], @config['settings']['indices']).select { |r| r.start_with?(*indices) }
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

  def do_snapshot(indices)
    indices.each do |index|
      next if skip_index?(index, 'snapshot')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        elastic_action_with_log('open_index', index) unless already?(response, 'open')
        elastic_action_with_log('delete_index', index) if elastic_action_with_log('snapshot_index', index)
      else
        log.warn "#{index} index not found"
      end
    end
  end

  def snapshot
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = snapshot_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_snapshot(indices)
  end
end
