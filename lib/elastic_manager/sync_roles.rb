# frozen_string_literal: true

module Sync
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
end