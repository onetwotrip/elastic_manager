# frozen_string_literal: true

# Index snapshots deleting operations
module SnapDelete

  def delete_snapshot(snapshot)
    snapshot = snapshot['snapshot']
    res = @elastic.request(:delete, "/_snapshot/#{@config['snapshot']['repos']['main']['name']}/#{snapshot}")

    if res.code == 200
      res = JSON.parse(res)
    else
      msg = "can't delete snapshot #{snapshot}: #{res}"
      log.error msg
      log_to_slack msg
      return false
    end

    if res['acknowledged'].is_a?(TrueClass)
      log.info "#{snapshot} delete success"
    else
      log.error "#{snapshot} delete error"
    end
  end

  def all_snapshots
    repo = @config['snapshot']['repos']['main']['name']
    res = @elastic.request(:get, "/_snapshot/#{repo}/_all")

    if res.code == 200
      JSON.parse(res)['snapshots']
    else
      log.fatal "can't get all snapshots: #{res}"
      exit 1
    end
  end

  def snapdelete
    unless @config['snapshot']['policy']
      log.error "there is no policies in config"
      exit 1
    end
    all_snapshots.each do |snapshot|
      index = snapshot['indices'].first
      policies = []

      @config['snapshot']['policy'].each do |_, policy|
        match = policy['index_patterns'].any? do |p|
          p = '.*' if p == '*'
          Regexp.new(p).match?(index)
        end
        policies << policy['days']['keep'] if match
      end

      if policies.length < 0
         msg = "can't find policy for snapshot:#{snapshot}, index:#{index}"
         log.error msg
         log_to_slack msg
         next
       elsif policies.length > 1
         msg = "too much policies for snapshot:#{snapshot}, index:#{index}"
         log.error msg
         log_to_slack msg
         next
       end

      begin
        snapshot_date = Date.parse(index.split('-').last)
      rescue ArgumentError
        log.error "can't parse date for snapshot:#{snapshot}, index:#{index}"
        next
      end

      today = Date.today
       if (today - snapshot_date) > policies.first
         delete_snapshot(snapshot)
       else
         log.info "no time to die #{snapshot['snapshot']}"
         next
       end
    end
  end
end