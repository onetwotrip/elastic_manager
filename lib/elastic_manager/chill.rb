# frozen_string_literal: true

require 'elastic_manager/logger'

# Index chilling operations
module Chill
  include Logging

  def chill_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, 'open', @config['settings']['box_types']['ingest'], @config['settings']['indices'])
    else
      if date_from.nil?
        result = @elastic.all_indices(date_from, date_to, daysago, 'open', @config['settings']['box_types']['ingest'], @config['settings']['indices']).select { |r| r.start_with?(*indices) }
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

  def do_chill(indices)
    indices.each do |index|
      next if skip_index?(index, 'chill')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already?(response, @config['settings']['box_types']['store'])

        elastic_action_with_log('chill_index', index, @config['settings']['box_types']['store'])
      else
        log.warn "#{index} index not found"
      end
    end
  end

  def chill
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = chill_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_chill(indices)
  end
end
