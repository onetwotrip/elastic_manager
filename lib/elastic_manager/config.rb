# frozen_string_literal: true

require 'json'
require 'yajl'
require 'elastic_manager/logger'

# Read, validate and merge with default config
module Config
  include Logging

  PARAMS = %w[
    TASK
    INDICES
    FROM
    TO
    DAYSAGO
    ES_URL
    TIMEOUT_WRITE
    TIMEOUT_CONNECT
    TIMEOUT_READ
    RETRY
    SLEEP
    FORCE
    SETTINGS
  ].freeze

  def make_default_config
    default = Hash.new { |hash, key| hash[key] = Hash.new(&hash.default_proc) }

    default['es']['url']          = 'http://127.0.0.1:9200'
    default['retry']              = '10'
    default['sleep']              = '60'
    default['force']              = 'false'
    default['timeout']['write']   = '2'
    default['timeout']['connect'] = '3'
    default['timeout']['read']    = '120'
    default['daysago']            = ''
    default['settings']           = {
      'box_types' => {
        'ingest' => 'hot',
        'store'  => 'warm'
      },
      'indices' => {}
    }

    log.debug "default config: #{default.inspect}"
    default
  end

  def check_settings(var, config)
    if var.casecmp('settings').zero?
      env_settings = json_parse(ENV[var])
      log.debug "env settings: #{env_settings}"
      config['settings'].merge(env_settings)
    else
      ENV[var]
    end
  end

  def env_parser(config)
    PARAMS.each do |var|
      next if ENV[var] == '' || ENV[var].nil?

      vars = var.split('_')

      if vars.length == 2
        config[vars[0].downcase][vars[1].downcase] = ENV[var]
      elsif vars.length == 1
        config[vars[0].downcase] = check_settings(vars[0], config)
      end
    end

    config
  end

  def validate_config(config)
    if config['task'].empty? || config['indices'].empty?
      fail_and_exit('not enough env variables: TASK, INDICES')
    end

    if !config['from'].empty? && !config['to'].empty?
      log.debug 'will use from and to'
      %w[from to].each do |key|
        config[key] = Date.strptime(config[key], '%Y-%m-%d')
      rescue ArgumentError => e
        fail_and_exit("can't parse date #{key}: #{e.message}")
      end
    elsif config['from'].empty? && !config['to'].empty?
      fail_and_exit('not enough env variables: FROM')
    elsif !config['from'].empty? && config['to'].empty?
      fail_and_exit('not enough env variables: TO')
    elsif !config['daysago'].empty?
      log.debug 'will use daysago'
      config['from'], config['to'] = nil
      config['daysago'] = config['daysago'].to_i
    else
      fail_and_exit('not enough env variables: FROM-TO or DAYSAGO')
    end

    config
  end

  def load_from_env
    log.debug 'will load config from ENV variables'

    config = make_default_config
    config = env_parser(config)
    config = validate_config(config)

    log.debug "env config: #{config.inspect}"
    config
  end
end
