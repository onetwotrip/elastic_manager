# frozen_string_literal: true

require 'json'
require 'yajl'

# Sharable methods
module Utils
  include Logging

  def true?(obj)
    obj.to_s.casecmp('true').zero?
  end

  def json_parse(string)
    JSON.parse(string)
  rescue JSON::ParserError => e
    log.fatal "json parse err: '''#{e.message}'''\n\t#{e.backtrace.join("\n\t")}"
    exit 1
  end

  def fail_and_exit(text)
    log.fatal text
    exit 1
  end

  def skip_index?(index, state)
    index_name = index.split('-')[0..-2].join('-')

    if @config['settings'][index_name] &&
       @config['settings'][index_name]['skip'] &&
       @config['settings'][index_name]['skip'][state]

      if true?(@config['settings'][index_name]['skip'][state])
        log.warn "#{index_name} index open skiped"
        return true
      end
    end

    false
  end

  def prepare_vars
    indices   = @config['indices'].split(',')
    daysago   = @config['daysago']
    date_from = @config['from']
    date_to   = @config['to']

    [indices, date_from, date_to, daysago]
  end

  def prechecks(date_from, date_to)
    unless date_from.nil?
      if date_from > date_to
        log.fatal "wrong dates: date to is behind date from. from: #{date_from}, to: #{date_to}"
        exit 1
      end
    end

    return if true?(@config['force'])
    return if @elastic.green?

    fail_and_exit("elasticsearch on #{@config['es']['url']} is not green")
  end
end
