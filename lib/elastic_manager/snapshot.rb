# frozen_string_literal: true

# Index snapshoting operations
module Snapshot

  def find_ilm_from_template(index)
    ilm = {}

    @config['templates'].each do |_, c|
      match = c['config']['index_patterns'].any? do |p|
        p = '.*' if p == '*'
        Regexp.new(p).match?(index)
      end
      ilm[c['config']['settings']['lifecycle']['name']] = c['config']['order'] if match
    end

    if ilm.keys.length < 1
      log.error "template for #{index} not found"
      return false
    elsif ilm.keys.length > 1
      return ilm.sort_by { |_, v| v }.to_h.keys.first
    end
    ilm.keys.first
  end

  def find_delete_age_in_ilm(ilm)
    age = false
    if @config['ilms'].key?(ilm)
      c = @config['ilms'][ilm]['config']

      if c['policy'] &&
        c['policy']['phases'] &&
        c['policy']['phases']['delete'] &&
        c['policy']['phases']['delete']['min_age']
        age = c['policy']['phases']['delete']['min_age'].tr('d', '').to_i
      else
        log.error "no delete phase for #{ilm}"
      end
    else
      log.error "no ilm #{ilm}"
    end
    age.to_i
  end

  def find_delete_age(index)
    ilm = find_ilm_from_template(index)
    return false unless ilm
    find_delete_age_in_ilm(ilm)
  end

  def find_delete_after(index)
    age = find_delete_age(index)
    return false unless age

    begin
      index_date = Date.parse(index.split('-').last)
    rescue ArgumentError
      return 1
    end

    delete_date = index_date + age
    today       = Date.today
    (delete_date - today).to_i
  end

  def get_snapshot(index)
    repo = @config['snapshot']['repos']['main']['name']
    snapshot_name = "snapshot_#{index}"
    res = @elastic.request(:get, "/_snapshot/#{repo}/#{snapshot_name}")

    if res.code == 200
      JSON.parse(res)['snapshots'][0]
    elsif res.code == 404
      log.warn "snapshot '#{snapshot_name}' not found in repo '#{repo}'"
      false
    else
      log.error "error gettings snapshot from elastic: #{res}"
      false
    end
  end

  def snapshot_repo_exist?
    res = @elastic.request(:get, '/_snapshot')
    if res.code == 200
      repos = JSON.parse(res)
      unless repos.empty?
        return true if repos.keys.include?(@config['snapshot']['repos']['main']['name'])
      end
    else
      log.error "dunno what to do with: #{res}"
    end
    false
  end

  def check_snapshot_repo
    unless snapshot_repo_exist?
      body = {
        'type' => @config['snapshot']['repos']['main']['type'],
        'settings' =>  {
          'location' => @config['snapshot']['repos']['main']['location']
        }
      }
      res = @elastic.request(:put, "/_snapshot/#{@config['snapshot']['repos']['main']['name']}", body)
      unless res.code == 200
        log.error "dunno what to do with: #{res}"
        return false
      end
    end
    true
  end

  def make_snapshot(index)
    return false unless check_snapshot_repo
    snapshot = get_snapshot(index)
    if snapshot
      if snapshot['state'] == 'SUCCESS'
        log.info "snapshot for index #{index} is already success"
        return true
      elsif snapshot['state'] == 'IN_PROGRESS'
        log.info "snapshot for index #{index} is already in progress"
        return true
      end
    end
    create_snapshot(index)
  end

  def wait_snapshot(snapshot)
    snapshot_ok = false

    until snapshot_ok
      sleep 30
      res = @elastic.request(:get, "/_snapshot/#{@config['snapshot']['repos']['main']['name']}/#{snapshot}/_status")

      if res.code == 200
        # TODO: (anton.ryabov) add logging of percent and time ?
        # stats = status['snapshots'][0]['stats']
        # msg = "(#{stats['total_size_in_bytes']/1024/1024/1024}Gb / #{stats['processed_size_in_bytes']/1024/1024/1024}Gb)"
        # puts "Get backup status #{msg}: retry attempt #{attempt_number}; #{total_delay.round} seconds have passed."
        state = JSON.parse(res)['snapshots'][0]['state']

        if state == 'SUCCESS'
          log.info "snapshot #{snapshot} success"
          snapshot_ok = true
        elsif %w[FAILED PARTIAL INCOMPATIBLE].include?(state)
          # TODO: (anton.ryabov) add slack notify due failed snapshot
          log.error "failed snapshot #{snapshot} in #{@config['snapshot']['repos']['main']['name']}: #{response}"
          return false
        end
      else
        log.error "can't check snapshot: #{response}"
        # TODO: (anton.ryabov) we need tries mechanizm here
      end
    end

    true
  end

  def create_snapshot(index)
    snapshot_name = "snapshot_#{index}"

    body = {
      'indices'              => CGI.unescape(index),
      'ignore_unavailable'   => false,
      'include_global_state' => false,
      'partial'              => false
    }

    res = @elastic.request(:put, "/_snapshot/#{@config['snapshot']['repos']['main']['name']}/#{snapshot_name}/", body)

    if res.code == 200
      wait_snapshot(snapshot_name)
    else
      log.error "can't snapshot #{index}: #{response}"
      false
    end
  end

  def snapshot
    indices = all_indices.keys
    indices.each do |index|
      will_delete_after = find_delete_after(index)
      unless will_delete_after
        # SLACK: ERR: can't snapshot index #{index}: can't detect delete date
        msg = "can't detect delete date for index '#{index}'"
        log.error msg
        log_to_slack msg
        next
      end

      if will_delete_after < 0
        msg = "index #{index} should have been deleted by ILM but he is not!"
        log.error msg
        log_to_slack msg
        # SLACK: ERR: "index #{index} should have been deleted by ILM but he is not!"
        next
      elsif will_delete_after < @config['snapshot']['repos']['main']['deadline']['soft']['days'] + 1
        unless make_snapshot(index)
          if @config['snapshot']['repos']['main']['deadline']['hard']['enabled']
            if will_delete_after < @config['snapshot']['repos']['main']['deadline']['hard']['days'] + 1
              msg = "can't snapshot index #{index} that will be deleted soon"
              log.error msg
              log_to_slack msg
              # VICTOR: "can't snapshot index #{index} that will be deleted soon"
              # SLACK: ERR: "index #{index} should have been deleted by ILM but he is not!"
              next
            else
              log.error "can't snapshot index #{index}"
              next
            end
          end
        end
      end
    end
  end
end
