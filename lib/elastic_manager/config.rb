require 'json'
require 'yajl'
require 'elastic_manager/logger'

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
    default['settings']           = {}

    log.debug "default config: #{default.inspect}"
    default
  end

  def check_settings(var)
    if var.casecmp('settings').zero?
      json_parse(ENV[var])
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
        config[vars[0].downcase] = check_settings(vars[0])
      end
    end

    config
  end

  def fail_and_exit
    log.fatal 'not enough env variables. TASK, INDICES, (FROM/TO or DAYSAGO)'
    exit 1
  end

  # def present?
  #   !blank?
  # end

  def exit_if_invalid(config)
    fail_and_exit if config['task'].empty? || config['indices'].empty?
    fail_and_exit unless (config['from'].empty? && config['to'].empty?) || config['daysago'].empty?
  end

  def load_from_env
    log.debug 'will load config from ENV variables'

    config = make_default_config
    config = env_parser(config)
    exit_if_invalid(config)

    log.debug "env config: #{config.inspect}"
    config
  end
end
