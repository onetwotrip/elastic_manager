# frozen_string_literal: true

module Sync

  TWIKET_USERS = %w[
    nginx
    logstash_internal
    apm_internal
  ].freeze

  def sync_users
    log.info 'sync users'
    elastic_users = JSON.parse(@elastic.request(:get, '/_security/user'))
    users_for_delete = []
    elastic_users.each do |user, params|
      next if params['metadata']['_reserved']
      next if TWIKET_USERS.include?(user)

      if @config['users'][user]
        if @config['users'][user].key?('retired') && @config['users'][user]['retired']
          log.warn "user '#{user}' retired"
        else
          next
        end
      end
      users_for_delete << user
    end
    log.info "will delete users: #{users_for_delete}"

    actual_users     = []
    users_for_create = []
    users_for_update = []

    @config['users'].each do |user, params|
      next if params['retired']
      actual_users << user
      if elastic_users[user]
        if @config['users'][user].key?('roles')
          next if (@config['users'][user]['roles'] - elastic_users[user]['roles']).length == 0
          users_for_update << user
        end
      else
        users_for_create << user
      end
    end
    log.info "will update users: #{users_for_update}"
    log.info "will create users: #{users_for_create}"

    sleep 3

    users_for_delete.each do |user|
      res = @elastic.request(:delete, "/_security/user/#{user}")
      log.info "delete #{user}: #{res}"
    end

    users_for_update.each do |ufu|
      elastic_users[ufu]['roles'] = (elastic_users[ufu]['roles'] + @config['users'][ufu]['roles']).uniq
      res = @elastic.request(:put, "/_security/user/#{ufu}", elastic_users[ufu])
      log.info "update #{ufu}: #{res}"
    end

    users_for_create.each do |ufc|
      roles = ['twiket_read_all']
      # TODO: (anton.ryabov) rewrite this hardcoded cluster check
      # roles << 'twiket_read_all' # if @config['env'] == 'development'
      roles = roles + @config['users'][ufc]['roles'] if @config['users'][ufc].key?('roles')

      user_hash = {
        password: SecureRandom.urlsafe_base64(24),
        roles:    roles
      }

      res = @elastic.request(:post, "/_security/user/#{ufc}", user_hash)
      log.info "create #{ufc}: #{res}"
    end

    TWIKET_USERS.each do |user|
      next if elastic_users[user]
      if @config['system_users'].key?(user) && @config['system_users'][user] != ''
        if @config['users'].key?(user) && @config['users'][user].key?('roles')
          user_hash = {
            password: @config['system_users'][user],
            roles:    @config['users'][user]['roles']
          }
          res = @elastic.request(:post, "/_security/user/#{user}", user_hash)
          log.info "create #{user}: #{res}"
        else
          log.warn "no roles for #{user} in vault"
        end
      else
        log.warn "no password for #{user} in vault"
      end
    end

    res = @elastic.request(:put, '/_security/role/nginx', { run_as: actual_users })
    log.info "update nginx role: #{res}"
  end
end