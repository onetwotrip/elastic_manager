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
    prefix        = "#{env}/elasticsearch"

    config = { 'env' => env }

    vault = Vault::Client.new(address: vault_address)
    vault.auth.approle(role_id.to_s, secret_id.to_s)

    kv = vault.kv('secret')
    
    vault_sys_users = kv.read("#{prefix}/system_users")
    raise 'no elastic system users in vault' if vault_sys_users.nil?
    config['system_users'] = JSON.parse(vault_sys_users.data.to_json)

    vault_roles = kv.read("#{prefix}/roles")
    raise 'no elastic roles in vault' if vault_roles.nil?
    config['roles'] = JSON.parse(vault_roles.data.to_json)

    vault_users = kv.read("#{prefix}/users")
    raise 'no elastic users in vault' if vault_users.nil?
    config['users'] = JSON.parse(vault_users.data.to_json)

    vault_ilm = kv.read("#{prefix}/ilms")
    raise 'no elastic ilm in vault' if vault_ilm.nil?
    config['ilms'] = JSON.parse(vault_ilm.data.to_json)

    vault_template = kv.read("#{prefix}/templates")
    raise 'no elastic template in vault' if vault_template.nil?
    config['templates'] = JSON.parse(vault_template.data.to_json)

    vault_spaces = kv.read("#{prefix}/spaces")
    raise 'no elastic template in vault' if vault_spaces.nil?
    config['spaces'] = JSON.parse(vault_spaces.data.to_json)

    vault_snapshot = kv.read("#{prefix}/snapshot")
    raise 'no elastic snapshot config in vault' if vault_snapshot.nil?
    config['snapshot'] = JSON.parse(vault_snapshot.data.to_json)

    vault_slack = kv.read("#{prefix}/slack")
    raise 'no elastic slack config in vault' if vault_slack.nil?
    config['slack'] = JSON.parse(vault_slack.data.to_json)

    vault_custom = kv.read("#{prefix}/custom")
    raise 'no elastic custom config in vault' if vault_custom.nil?
    config['custom'] = JSON.parse(vault_custom.data.to_json)

    vault_privileges = kv.read("#{prefix}/privileges")
    raise 'no elastic privileges config in vault' if vault_privileges.nil?
    config['privileges'] = JSON.parse(vault_privileges.data.to_json)

    config
  end
end
