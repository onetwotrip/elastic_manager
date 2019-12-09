# frozen_string_literal: true

require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
# require 'elastic_manager/utils'
# require 'elastic_manager/open'
# require 'elastic_manager/close'
# require 'elastic_manager/chill'
require 'elastic_manager/snapshot'
require 'elastic_manager/sync_roles'
require 'elastic_manager/sync_users'
require 'elastic_manager/sync_ilms'
require 'elastic_manager/sync_templates'
require 'elastic_manager/sync_spaces'
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
  include Snapshot
  include Sync
  # include Delete
  # include SnapDelete

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

  def snapdelete
    log.warn 'command snapdelete not implemented yet'
    # get config for snapdelete
    # get all snapshots
    # iterate all snapshots
    #   if snapshot date later then days in config
    #     delete snapshot
    #   else
    #     next
    #   end
    # end
    # exit if can't get all indices
    # log and log to slack if can't get config
    # log and log to slack if can't all snapshots
    # log to slack if can't delete
  end

  def open
    log.warn 'command open not implemented yet'
    # get parameters
    # prepare indices array
    # iterate indices
    #   next if index exist and open
    #   unfreeze if index exist and frozen
    #   else add to need snapshot queue
    # end
    # iterate snapshot queue
    #   restore if snapshot exist
    #   log to slack if no snapshot found
    # end
    # exit if bad parameters
    # prepare exit code
  end
end
