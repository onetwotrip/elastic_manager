# frozen_string_literal: true

require 'elastic_manager/logger'

# Index opening operations
module Open
  include Logging

  def open_prechecks(date_from, date_to)
    unless date_from.nil?
      if date_from > date_to
        log.fatal "wrong dates: date to is behind date from. from: #{date_from}, to: #{date_to}"
        exit 1
      end
    end

    unless true?(@config['force']) && @elastic.green?
      fail_and_exit("elasticsearch on #{@config['es']['url']} is not green")
    end
  end

  def skip_open?(index)
    index_name = index.split('-')[0..-2].join('-')

    if @config['settings'][index_name] && @config['settings'][index_name]['skip_open']
      if true?(@config['settings'][index_name]['skip_open'])
        log.warn "#{index_name} index open skiped"
        return true
      end
    end

    false
  end

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

  def open_prepare_vars
    indices   = @config['indices'].split(',')
    daysago   = @config['daysago'].to_i
    date_from = @config['from']
    date_to   = @config['to']

    date_from = date_from.empty? ? nil : Date.parse(date_from)
    date_to   = date_to.empty? ? nil : Date.parse(date_to)

    [indices, date_from, date_to, daysago]
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
          result << "#{index}-#{date.to_s.tr!('-', '.')}"
        end
      end
    end

    return result unless result.empty?

    log.fatal 'no indices for work'
    exit 1
  end

  def do_open(indices)
    indices.each do |index|
      next if skip_open?(index)

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
    indices, date_from, date_to, daysago = open_prepare_vars
    open_prechecks(date_from, date_to)
    indices = populate_indices(indices, date_from, date_to, daysago)

    log.debug indices.inspect

    do_open(indices)
  end
end
