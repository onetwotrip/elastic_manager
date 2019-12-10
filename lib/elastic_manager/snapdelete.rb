# frozen_string_literal: true

# Index snapshots deleting operations
module SnapDelete

  def delete_snapshot(snapshot)
    snapshot = snapshot['snapshot']
    res = @elastic.request(:delete, "/_snapshot/#{@config['snapshot']['repos']['main']['name']}/#{snapshot}")

    if res.code == 200
      JSON.parse(res)
    else
      log.error "can't delete snapshot #{snapshot}: #{res}"
      return false
    end

    res['acknowledged'].is_a?(TrueClass)
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
end