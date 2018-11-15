# frozen_string_literal: true

require 'elastic_manager/logger'

# Index opening operations
module Open
  include Logging

  def index_exist?(response)
    if response.code == 200
      true
    elsif response.code == 404
      false
    else
      log.fatal "wtf in index_exist? response was: #{response.code} - #{response}"
      exit 1
    end
  end

  def already_open?(response)
    index = json_parse(response).first
    if index['status'] == 'open'
      log.warn "#{index['index']} index status already open"
      return true
    end

    false
  end

  def action_with_log(action, index)
    if @elastic.send(action, index)
      log.info "#{index} #{action} succes"
    else
      log.error "#{index} #{action} fail"
    end
  end

  def populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices(date_from, date_to, daysago, 'close')
      result += @elastic.all_indices_in_snapshots(date_from, date_to, daysago)
      return result
    end

    if date_from.nil?
      result = @elastic.all_indices(date_from, date_to, daysago, 'close')
      result += @elastic.all_indices_in_snapshots(date_from, date_to, daysago)
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
    indices.each do |index|
      next if skip_index?(index, 'open')

      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already_open?(response)

        action_with_log('open_index', index)
      else
        log.warn "#{index} index not found"
        log.info "#{index} trying snapshot restore"

        action_with_log('restore_snapshot', index)
      end
    end
  end

  def open
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = populate_indices(indices, date_from, date_to, daysago)

    log.debug indices.inspect

    do_open(indices)
  end
end
