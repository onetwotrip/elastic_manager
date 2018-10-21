require 'json'
require 'yajl'

module Utils
  include Logging

  REVERT_STATE = {
    'open'  => 'close',
    'close' => 'open'
  }

  def true?(obj)
    obj.to_s.downcase == 'true'
  end

  def json_parse(string)
    JSON.parse(string)
  rescue JSON::ParserError => e
    log.fatal "json parse err: '''#{e.message}'''\n\t#{e.backtrace.join("\n\t")}"
    exit 1
  end

  def prechecks(date_from, date_to)
    if date_from > date_to
      log.fatal "wrong dates: date to is behind date from. from: #{date_from}, to: #{date_to}"
      exit 1
    end

    unless true?(@config['force'])
      unless @elastic.green?
        log.fatal "elasticsearch on #{@config['es']['url']} is not green"
        exit 1
      end
    end
  end

  def prepare_vars
    indices   = @config['indices'].split(',')
    date_from = Date.parse(@config['from'])
    date_to   = Date.parse(@config['to'])

    return indices, date_from, date_to
  end

  def all_precheck(indices, date_from, date_to, state)
    if indices.length == 1 && indices.first == '_all'
      indices = @elastic.all_indices(date_from, date_to, state)
    end

    indices
  end

  def action_with_log(action, index)
    if @elastic.index(action, index)
      log.info "#{index} #{action} succes"
    else
      log.error "#{index} #{action} fail"
    end
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

  def already?(status, response, index)
    if json_parse(response).first['status'] == status
      log.warn "#{index} index status already #{status}"
      return true
    end

    false
  end

  def skip?(status, index_name)
    if @config['settings'][index_name]
      if @config['settings'][index_name]['skip'][status]
        log.debug @config['settings'][index_name]['skip'][status].inspect

        if true?(@config['settings'][index_name]['skip'][status])
          log.warn "#{index_name} index #{status} skiped"
          return true
        end
      end
    end

    false
  end

  def action(task)
    indices, date_from, date_to = prepare_vars
    prechecks(date_from, date_to)
    indices = all_precheck(indices, date_from, date_to, REVERT_STATE[task])

    date_from.upto(date_to) do |date|
      self.send("do_#{task}", indices, date.to_s.tr!('-', '.'))
    end
  end
end
