# frozen_string_literal: true

require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/slack'
require 'elastic_manager/snapshot'
require 'elastic_manager/sync_roles'
require 'elastic_manager/sync_users'
require 'elastic_manager/sync_ilms'
require 'elastic_manager/sync_templates'
require 'elastic_manager/sync_spaces'
require 'elastic_manager/snapdelete'
require 'elastic_manager/open'

# Main
class ElasticManager
  include Config
  include Logging
  include Request
  include LogToSlack
  include Snapshot
  include SnapDelete
  include Sync
  include Open

  def initialize
    @config  = prepare_config
    @elastic = Request::Elastic.new(@config['system_users']['elastic'])
    @kibana  = Request::Kibana.new(@config['system_users']['elastic'])
  end

  def all_indices
    url = '/_cluster/state/metadata/'
    url = "#{url}?filter_path=metadata.indices.*.state,"
    url = "#{url}metadata.indices.*.settings.index.routing.allocation.require.box_type"

    res = @elastic.request(:get, url)
    if res.code == 200
      JSON.parse(res)['metadata']['indices']
    else
      log.error "can't get all indices: #{res.code} - #{res.body}"
      false
    end
  end
end
