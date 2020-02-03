# frozen_string_literal: true

module Sync
  def sync_privileges
    log.info 'sync privileges'

    @config['privileges'].each do |application, privilege|
      privilege.each do |name, params|

        privilege_body = {
          application => {
            name => params
          }
        }

        elastic_privilege_res = @elastic.request(:get, "/_security/privilege/#{params['application']}/#{name}")
        elastic_privilege = JSON.parse(elastic_privilege_res)

        if privilege_body == elastic_privilege
          log.info "privilege '#{name}' for application '#{application}' is exist and already synced"
        else
          privilege_body['kibana-.kibana']['feature_create_short_url.all'].delete('application')
          privilege_body['kibana-.kibana']['feature_create_short_url.all'].delete('name')

          log.info "will update privilege '#{name}' for application '#{application}'"
          res = @elastic.request(:put, '/_security/privilege', privilege_body)
          puts res
        end
      end
    end
  end
end
