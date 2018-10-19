require 'dotenv/load'
require 'date'
require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/utils'

class ElasticManager
  include Config
  include Logging
  include Request
  include Utils

  # attr_reader :config

  def initialize(argv)
    if argv.size == 0
      @config = load_from_env
    else
      @config = load_from_argv
    end

    @elastic = Request::Elastic.new(@config)
  end

  def open_prechecks(indices, date_from, date_to)
    unless date_from < date_to
      log.fatal "wrong dates: date to is behind date from. from: #{date_from}, to: #{date_to}"
      exit 1
    end

    unless true?(@config['force'])
      unless @elastic.green?
        log.fatal "elasticsearch on #{@config['es']['url']} is not green"
        exit 1
      end
    end

    if indices.length == 1 && indices.first == '_all'
      indices = @elastic.all_indices(date_from, date_to, 'close')
    end

    indices
  end

  def skip_open?(index_name)
    if @config['settings'][index_name]
      if @config['settings'][index_name]['skip_open']
        log.debug @config['settings'][index_name]['skip_open'].inspect

        if true?(@config['settings'][index_name]['skip_open'])
          log.warn "#{index_name} index open skiped"
          return true
        end
      end
    end

    false
  end

  def index_exist?(response)
    if response.code == 200
      return true
    elsif response.code == 404
      return false
    else
      log.fatal "wtf in index_exist? response was: #{response.code} - #{response}"
      exit 1
    end
  end

  def already_open?(response)
    if response.body.to_s =~ /open/
      log.warn "#{index} index already opened"
      return true
    end

    false
  end

  def open_prepare_vars
    indices   = @config['indices'].split(',')
    date_from = Date.parse(@config['from'])
    date_to   = Date.parse(@config['to'])
    indices   = open_prechecks(indices, date_from, date_to)

    return indices, date_from, date_to
  end

  def action_with_log(action, index)
    if @elastic.send(action, index)
      log.info "#{index} #{action} succes"
    else
      log.error "#{index} #{action} fail"
    end
  end

  def open(indices, date)
    indices.each do |index_name|
      next if skip_open?(index_name)

      index    = "#{index_name}-#{date}"
      response = request(:get, "/_cat/indices/#{index}")

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

  def do_open
    indices, date_from, date_to = open_prepare_vars

    date_from.upto(date_to) do |date|
      open(indices, date.to_s.tr!('-', '.'))
    end
  end

  def run
    if @config['task'].downcase == 'open'
      do_open
    end
  end
end
