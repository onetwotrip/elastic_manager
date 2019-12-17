# frozen_string_literal: true

# Index opening operations
module Open

  def parse_dates
    c = {} # c for config
    %w[from to].each do |key|
      val = ENV[key.upcase].strip
      begin
        c[key] = Date.parse(val.delete('-'))
      rescue ArgumentError
        log.error "can't parse date '#{key}': '#{val}'"
        exit 1
      end
    end
    [c['from'], c['to']]
  end

  def check_env_variables
    if ENV['INDICES'] == '' || ENV['FROM'] == '' || ENV['TO'] == ''
      log.error 'ENV variables INIDICES, FROM, TO must be provided'
      exit 1
    end
  end

  def generate_params
    indices = ENV['INDICES'].split(',').map(&:strip)
    from, to = parse_dates
    [indices, from, to]
  end

  def check_dates(from, to)
    if from > to
      log.fatal "date to '#{to}' is behind date from '#{from}'"
      exit 1
    end
  end

  def generate_indices(prefixes, from, to)
    indices = []
    from.upto(to) do |date|
      prefixes.each do |index|
        indices << "#{index}-#{date.to_s.tr('-', '.')}"
      end
    end
    indices
  end

  def index_state(index)
    res = @elastic.request(:get, "/_cat/indices/#{index}")
    return 'notfound' if res.code == 404

    if res.code == 200
      state = JSON.parse(res).first['state']
      res = @elastic.request(:get, "/#{index}")
      if res.code == 200
        index_settings = JSON.parse(res)[index]['settings']['index']
        if index_settings['frozen']
          'frozen'
        else
          state
        end
      else
        log.error "can't get index: '#{res}'"
        'fail'
      end
    else
      log.error "can't get index status: '#{res}'"
      'fail'
    end
  end

  def open_index(index)
    res = @elastic.request(:post, "/#{index}/_open?master_timeout=1m")

    if res.code == 200
      res = JSON.parse(res)
      if res['acknowledged'].is_a?(TrueClass)
        log.info "index '#{index}' open success"
        true
      else
        log.error "index '#{index}' open error: #{res}"
        false
      end
    else
      log.error "wrong response code for opening '#{index}': '#{res}'"
      false
    end

  end

  def unfreeze_index(index)
    res = @elastic.request(:post, "/#{index}/_unfreeze?master_timeout=1m")

    if res.code == 200
      res = JSON.parse(res)
      if res['acknowledged'].is_a?(TrueClass)
        log.info "index '#{index}' unfreeze success"
        true
      else
        log.error "index '#{index}' unfreeze error: #{res}"
        false
      end
    else
      log.error "wrong response code for unfreezing '#{index}': '#{res}'"
      false
    end
  end

  def process_open(indices)
    snapshot_queue = []
    results        = []

    indices.each do |index|
      state = index_state(index)
      next if state == 'fail' || state == 'open'
      results << open_index(index) if state == 'close'
      results << unfreeze_index(index) if state == 'frozen'
      snapshot_queue << index if state == 'notfound'
    end

    [results, snapshot_queue]
  end

  def stop_ilm
    res = @elastic.request(:post, '/_ilm/stop')
    if res.code == 200
      log.info 'ILM stopped'
    else
      log.error "can't stop ILM: #{res}"
      exit 1
    end

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = false

    loop do
      break if timeout_exceed(start)
      sleep 30

      res = @elastic.request(:get, "/_ilm/status")

      if res.code == 200
        if JSON.parse(res)['operation_mode'] == 'STOPPED'
          result = true
          break
        end
      else
        log.error "can't check ILM status: #{res}"
      end
    end

    unless result
      log.error "can't stop ILM"
      exit 1
    end
  end

  def snapshot_exist?(index)
    snapshot_name = "snapshot_#{index}"
    repo = @config['snapshot']['repos']['main']['name']
    res = @elastic.request(:get, "/_snapshot/#{repo}/#{snapshot_name}")

    if res.code == 200
      true
    elsif res.code == 404
      false
    else
      log.error "can't check snapshot existing: #{res}"
      false
    end
  end

  def restore_snapshot(index)
    snapshot_name = "snapshot_#{index}"
    repo = @config['snapshot']['repos']['main']['name']

    body = {
      index_settings: {
        'index.number_of_replicas'                  => 0,
        'index.refresh_interval'                    => -1,
        'index.routing.allocation.require.box_type' => 'warm'
      }
    }
    res = @elastic.request(:post, "/_snapshot/#{repo}/#{snapshot_name}/_restore", body)

    if res.code == 200
      sleep 5
      wait_snapshot_restore(index)
    else
      log.error "can't restore snapshot #{snapshot_name}: #{res}"
      false
    end
  end

  def timeout_exceed(start, t=600)
    if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to_i > t
      log.error 'timeout exceed for creating'
      return true
    end
    false
  end

  def wait_snapshot_restore(index)
    snapshot_name = "snapshot_#{index}"
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = false

    loop do
      break if timeout_exceed(start)
      sleep 30

      res = @elastic.request(:get, "/#{snapshot_name}/_recovery")

      if res.code == 200
        # TODO: (anton.ryabov) add logging of percent and time ?

        if JSON.parse(res)[index]['shards'].map { |s| s['stage'] == 'DONE' }.all? { |a| a }
          result = true
          break
        end
      else
        log.error "can't check '#{snapshot_name}' recovery: #{res}"
      end
    end

    result
  end

  def process_snapshot(results, snapshot_queue)
    snapshot_notfound = []
    snapshot_queue.each do |index|
      if snapshot_exist?(index)
        results << restore_snapshot(index)
      else
        snapshot_notfound << index
      end
    end
    [results, snapshot_notfound]
  end

  def index_state_old(index, oe)
    res = oe.request(:get, "/_cat/indices/#{index}")
    return 'notfound' if res.code == 404

    if res.code == 200
      JSON.parse(res).first['state']
    else
      log.error "can't get index status: '#{res}'"
      'fail'
    end
  end

  def open_index_old(index, oe)
    res = oe.request(:post, "/#{index}/_open?master_timeout=1m")

    if res.code == 200
      res = JSON.parse(res)
    else
      log.error "wrong response code for opening '#{index}': '#{res}'"
      return false
    end
    res['acknowledged'].is_a?(TrueClass)
  end

  def restore_snapshot_old(index, oe)
    snapshot_name = "snapshot_#{index}"
    repo = @config['custom']['old_cluster']['repo']

    body = {
      index_settings: {
        'index.number_of_replicas'                  => 0,
        'index.refresh_interval'                    => -1,
        'index.routing.allocation.require.box_type' => 'warm'
      }
    }
    res = oe.request(:post, "/_snapshot/#{repo}/#{snapshot_name}/_restore", body)

    if res.code == 200
      sleep 5
      wait_snapshot_restore_old(index, oe)
    else
      log.error "can't restore snapshot #{snapshot_name}: #{res}"
      false
    end
  end

  def wait_snapshot_restore_old(index, oe)
    snapshot_name = "snapshot_#{index}"
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = false

    loop do
      break if timeout_exceed(start)
      sleep 30

      res = oe.request(:get, "/#{snapshot_name}/_recovery")

      if res.code == 200
        # TODO: (anton.ryabov) add logging of percent and time ?

        if JSON.parse(res)[index]['shards'].map { |s| s['stage'] == 'DONE' }.all? { |a| a }
          result = true
          break
        end
      else
        log.error "can't check '#{snapshot_name}' recovery: #{res}"
      end
    end

    result
  end

  def process_old(results, indices)
    # oe - old elatic
    oe = Request::Elastic.new(
      @config['custom']['old_cluster']['pass'],
      @config['custom']['old_cluster']['url']
    )

    indices.each do |index|
      state = index_state_old(index, oe)
      next if state == 'fail' || state == 'open'
      results << open_index_old(index, oe) if state == 'close'
      results << restore_snapshot_old(index, oe) if state == 'notfound'
    end

    results
  end

  def process_indices(indices)
    stop_ilm
    results, snapshot_queue = process_open(indices)

    snapshot_notfound = []
    unless snapshot_queue.empty?
      results, snapshot_notfound = process_snapshot(results, snapshot_queue)
    end

    unless snapshot_notfound.empty?
      if @config['custom']['old_cluster'] == 'true'
        results = process_old(results, snapshot_notfound)
      else
        snapshot_notfound.each do |index|
          log.error "can't find snapshot for '#{index}'"
          results << false
        end
      end
    end
    results
  end

  def open
    check_env_variables
    index_prefixes, from, to = generate_params
    check_dates(from, to)
    indices = generate_indices(index_prefixes, from, to)
    results = process_indices(indices)

    exit 1 if results.all? { |e| e.is_a?(FalseClass) }
    # It is little bit confusing, but we catch exit code 2 in jenkins
    # for mark build as unstable instead of just fail it
    exit 2 if results.any? { |e| e.is_a?(FalseClass) }
  end
end
