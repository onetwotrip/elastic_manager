# frozen_string_literal: true

require 'json'
require 'yajl'
require 'elastic_manager/logger'
require 'vault'
require 'dotenv/load'

# Read, validate and merge with default config
module Config
  include Logging

  def prepare_config
    vault_address = ENV.fetch('VAULT_URL')
    role_id       = ENV.fetch('VAULT_ROLE_ID')
    secret_id     = ENV.fetch('VAULT_SECRET_ID')
    env           = ENV.fetch('ELK_ENV')
    prefix        = "#{ENV.fetch('VAULT_PREFIX')}/#{env}/elasticsearch"

    config = { 'env' => env }

    vault = Vault::Client.new(address: vault_address)
    vault.auth.approle(role_id.to_s, secret_id.to_s)

    vault_sys_users = vault.logical.read("#{prefix}/system_users")
    raise 'no elastic system users in vault' if vault_sys_users.nil?
    config['system_users'] = JSON.parse(vault_sys_users.data.to_json)

    vault_roles = vault.logical.read("#{prefix}/roles")
    raise 'no elastic roles in vault' if vault_roles.nil?
    config['roles'] = JSON.parse(vault_roles.data.to_json)

    vault_users = vault.logical.read("#{prefix}/users")
    raise 'no elastic users in vault' if vault_users.nil?
    config['users'] = JSON.parse(vault_users.data.to_json)

    vault_ilm = vault.logical.read("#{prefix}/ilms")
    raise 'no elastic ilm in vault' if vault_ilm.nil?
    config['ilms'] = JSON.parse(vault_ilm.data.to_json)

    vault_template = vault.logical.read("#{prefix}/templates")
    raise 'no elastic template in vault' if vault_template.nil?
    config['templates'] = JSON.parse(vault_template.data.to_json)

    vault_spaces = vault.logical.read("#{prefix}/spaces")
    raise 'no elastic template in vault' if vault_spaces.nil?
    config['spaces'] = JSON.parse(vault_spaces.data.to_json)

    vault_snapshot = vault.logical.read("#{prefix}/snapshot")
    raise 'no elastic snapshot config in vault' if vault_snapshot.nil?
    config['snapshot'] = JSON.parse(vault_snapshot.data.to_json)

    vault_slack = vault.logical.read("#{prefix}/slack")
    raise 'no elastic slack config in vault' if vault_slack.nil?
    config['slack'] = JSON.parse(vault_slack.data.to_json)

    config
  end

  # PARAMS = %w[
  #   TASK
  #   INDICES
  #   FROM
  #   TO
  #   DAYSAGO
  #   ES_URL
  #   TIMEOUT_WRITE
  #   TIMEOUT_CONNECT
  #   TIMEOUT_READ
  #   RETRY
  #   SLEEP
  #   FORCE
  #   SETTINGS
  # ].freeze
  #
  # def make_default_config
  #   default = Hash.new { |hash, key| hash[key] = Hash.new(&hash.default_proc) }
  #
  #   default['es']['url']          = 'http://127.0.0.1:9200'
  #   default['retry']              = '10'
  #   default['sleep']              = '30'
  #   default['force']              = 'false'
  #   default['timeout']['write']   = '2'
  #   default['timeout']['connect'] = '3'
  #   default['timeout']['read']    = '120'
  #   default['daysago']            = ''
  #   default['settings']           = {
  #     'box_types' => {
  #       'ingest' => 'hot',
  #       'store'  => 'warm'
  #     },
  #     'indices' => {}
  #   }
  #
  #   log.debug "default config: #{default.inspect}"
  #   default
  # end
  #
  # def check_settings(var, config)
  #   if var.casecmp('settings').zero?
  #     settings     = ENV[var]
  #     env_settings = json_parse(File.file?(settings) ? File.read(settings) : settings)
  #     log.debug "env settings: #{env_settings}"
  #     config['settings'].merge(env_settings)
  #   else
  #     ENV[var]
  #   end
  # end
  #
  # def env_parser(config)
  #   PARAMS.each do |var|
  #     next if ENV[var] == '' || ENV[var].nil?
  #
  #     vars = var.split('_')
  #
  #     if vars.length == 2
  #       config[vars[0].downcase][vars[1].downcase] = ENV[var]
  #     elsif vars.length == 1
  #       config[vars[0].downcase] = check_settings(vars[0], config)
  #     end
  #   end
  #
  #   config
  # end
  #
  # def validate_config(config)
  #   if config['task'].empty? || config['indices'].empty?
  #     fail_and_exit('not enough env variables: TASK, INDICES')
  #   end
  #
  #   if !config['from'].empty? && !config['to'].empty?
  #     log.debug 'will use from and to'
  #     %w[from to].each do |key|
  #       config[key] = Date.strptime(config[key], '%Y-%m-%d')
  #     rescue ArgumentError => e
  #       fail_and_exit("can't parse date #{key}: #{e.message}")
  #     end
  #   elsif config['from'].empty? && !config['to'].empty?
  #     fail_and_exit('not enough env variables: FROM')
  #   elsif !config['from'].empty? && config['to'].empty?
  #     fail_and_exit('not enough env variables: TO')
  #   elsif !config['daysago'].empty?
  #     log.debug 'will use daysago'
  #     config['from'], config['to'] = nil
  #     config['daysago'] = config['daysago'].to_i
  #   else
  #     fail_and_exit('not enough env variables: FROM-TO or DAYSAGO')
  #   end
  #
  #   config
  # end
  #
  # def load_from_env
  #   log.debug 'will load config from ENV variables'
  #
  #   config = make_default_config
  #   config = env_parser(config)
  #   config = validate_config(config)
  #
  #   log.debug "env config: #{config.inspect}"
  #   config
  # end
end
