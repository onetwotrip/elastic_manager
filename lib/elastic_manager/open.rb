# frozen_string_literal: true

require 'elastic_manager/logger'

# Index opening operations
module Open
  include Logging

  def open_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, 'close', nil, @config)
      result += @elastic.all_indices_in_snapshots(date_from, date_to, daysago, @config)
      return result
    end

    if date_from.nil?
      result = @elastic.all_indices(date_from, date_to, daysago, 'close', nil, @config)
      result += @elastic.all_indices_in_snapshots(date_from, date_to, daysago, @config)
      return result.select { |r| r.start_with?(*indices) }
    else
      date_from.upto(date_to) do |date|
        indices.each do |index|
          date_formatted = date.to_s.tr('-', '.')
          result << "#{index}-#{date_formatted}"
        end
      end
    end

    return result unless result.empty?

    log.fatal 'no indices for work'
    exit 1
  end

  def do_open(indices)
    results = []

    indices.each do |index|
      next if skip_index?(index, 'open')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already?(response, 'open')

        results << elastic_action_with_log('open_index', index)
      else
        log.warn "#{index} index not found"
        log.info "#{index} trying snapshot restore"

        results << elastic_action_with_log('restore_snapshot', index, @config['settings']['box_types']['store'])
      end
    end

    exit 1 if results.any? { |e| e.is_a?(FalseClass) }
  end

  def open
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = open_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_open(indices)
  end
end
