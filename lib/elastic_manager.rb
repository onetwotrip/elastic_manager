# frozen_string_literal: true

require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
# require 'elastic_manager/utils'
# require 'elastic_manager/open'
# require 'elastic_manager/close'
# require 'elastic_manager/chill'
# require 'elastic_manager/snapshot'
# require 'elastic_manager/delete'
# require 'elastic_manager/snapdelete'

# Main
class ElasticManager
  include Config
  include Logging
  include Request
  # include Utils
  # include Open
  # include Close
  # include Chill
  # include Snapshot
  # include Delete
  # include SnapDelete

  TWIKET_USERS = %w[
    nginx
    logstash_internal
  ].freeze

  def initialize
    @config  = prepare_config
    @elastic = Request::Elastic.new(@config['system_users']['elastic'])
  end

  def sync_roles
    log.info 'sync roles'
    elastic_roles = JSON.parse(@elastic.request(:get, '/_xpack/security/role'))
    roles_for_delete = []
    elastic_roles.each do |role, params|
      next if params['metadata']['_reserved']
      next if role == 'nginx'

      if @config['roles'][role]
        if @config['roles'][role].key?('retired') && @config['roles'][role]['retired']
          log.warn "role '#{role}' retired"
        else
          next
        end
      end
      roles_for_delete << role
    end
    log.info "will delete roles: #{roles_for_delete}"

    roles_for_create = []
    @config['roles'].each do |role, params|
      next if params['retired']
      roles_for_create << role
    end
    log.info "will put roles: #{roles_for_create}"

    sleep 3

    roles_for_delete.each do |role|
      res = @elastic.request(:delete, "/_xpack/security/role/#{role}")
      log.info "delete #{role}: #{res}"
    end

    # TODO: (anton.ryabov) mb diff before and put only if changed?
    roles_for_create.each do |role|
      res = @elastic.request(:put, "/_xpack/security/role/#{role}", @config['roles'][role]['config'])
      log.info "create #{role}: #{res}"
    end
  end

  def sync_users
    log.info 'sync users'
    elastic_users = JSON.parse(@elastic.request(:get, '/_xpack/security/user'))
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
      res = @elastic.request(:delete, "/_xpack/security/user/#{user}")
      log.info "delete #{user}: #{res}"
    end

    users_for_update.each do |ufu|
      elastic_users[ufu]['roles'] = (elastic_users[ufu]['roles'] + @config['users'][ufu]['roles']).uniq
      res = @elastic.request(:put, "/_xpack/security/user/#{ufu}", elastic_users[ufu])
      log.info "update #{ufu}: #{res}"
    end

    users_for_create.each do |ufc|
      roles = ['kibana_user']
      # TODO: (anton.ryabov) rewrite this hardcoded cluster check
      roles << 'twiket_read_all' if @config['cluster'] == 'devlogs'
      roles = roles + @config['users'][ufc]['roles'] if @config['users'][ufc].key?('roles')

      user_hash = {
        password: SecureRandom.urlsafe_base64(24),
        roles:    roles
      }

      res = @elastic.request(:post, "/_xpack/security/user/#{ufc}", user_hash)
      log.info "create #{ufc}: #{res}"
    end

    res = @elastic.request(:put, '/_xpack/security/role/nginx', { run_as: actual_users })
    log.info "update nginx role: #{res}"
  end

  def sync_ilms
    log.info 'sync ilm'
    elastic_ilm = JSON.parse(@elastic.request(:get, '/_ilm/policy'))
    ilm_for_delete = []
    elastic_ilm.keys.each do |ilm|
      # we can't check reserved ilm, so will process only custom ilm starts with twiket
      # due this any custom ilm must be named with twiket prefix
      next unless ilm.start_with?('twiket')

      if @config['ilm'][ilm]
        if @config['ilm'][ilm].key?('retired') && @config['ilm'][ilm]['retired']
          log.warn "ilm '#{ilm}' retired"
        else
          next
        end
      end
      ilm_for_delete << ilm
    end
    log.info "will delete ilm: #{ilm_for_delete}"

    ilm_for_create = []
    @config['ilm'].each do |ilm, params|
      next if params['retired']
      ilm_for_create << ilm
    end
    log.info "will put ilm: #{ilm_for_create}"

    sleep 3

    ilm_for_delete.each do |ilm|
      res = @elastic.request(:delete, "/_ilm/policy/#{ilm}")
      log.info "delete #{ilm}: #{res}"
    end

    # TODO: (anton.ryabov) mb diff before and put only if changed?
    # elastic will accept each request and increment policy version even if no difference in policies
    # how big number they have for version?
    ilm_for_create.each do |ilm|
      res = @elastic.request(:put, "/_ilm/policy/#{ilm}", @config['ilm'][ilm]['config'])
      log.info "create #{ilm}: #{res}"
    end
  end

  def sync_templates
    log.info 'sync template'
    elastic_template = JSON.parse(@elastic.request(:get, '/_template'))
    template_for_delete = []
    elastic_template.keys.each do |template|
      # we can't check reserved template, so will process only custom template starts with twiket
      # due this any custom template must be named with twiket prefix
      next unless template.start_with?('twiket')

      if @config['template'][template]
        if @config['template'][template].key?('retired') && @config['template'][template]['retired']
          log.warn "template '#{template}' retired"
        else
          next
        end
      end
      template_for_delete << template
    end
    log.info "will delete template: #{template_for_delete}"

    template_for_create = []
    @config['template'].each do |template, params|
      next if params['retired']
      template_for_create << template
    end
    log.info "will put template: #{template_for_create}"

    sleep 3

    template_for_delete.each do |template|
      res = @elastic.request(:delete, "/_template/#{template}")
      log.info "delete #{template}: #{res}"
    end

    # TODO: (anton.ryabov) mb diff before and put only if changed?
    # template must have index patterns
    template_for_create.each do |template|
      res = @elastic.request(:put, "/_template/#{template}", @config['template'][template]['config'])
      log.info "create #{template}: #{res}"
    end
  end

  def snapshot
    log.warn 'command snapshot not implemented yet'
  end

  def snapdelete
    log.warn 'command snapdelete not implemented yet'
  end

  def open
    log.warn 'command open not implemented yet'
  end
end
