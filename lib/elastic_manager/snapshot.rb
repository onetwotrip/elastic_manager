# frozen_string_literal: true

# Index snapshoting operations
module Snapshot

  def find_ilm_from_template(index)
    ilm = []

    @config['template'].each do |_, c|
      match = c['config']['index_patterns'].any? { |p| Regexp.new(p).match?(index) }
      ilm << c['config']['settings']['index.lifecycle.name'] if match
    end

    if ilm.length < 1
      log.error "template for #{index} not found"
      return false
    elsif ilm.length > 1
      log.error "too much templates for #{index}"
      return false
    end
    ilm.first
  end

  def find_delete_age_in_ilm(ilm)
    age = false
    if @config['ilm'].key?(ilm)
      c = @config['ilm'][ilm]['config']

      if c['policy'] &&
        c['policy']['phases'] &&
        c['policy']['phases']['delete'] &&
        c['policy']['phases']['delete']['min_age']
        age = conf['policy']['phases']['delete']['min_age'].tr('d', '').to_i
      else
        log.error "no delete phase for #{ilm}"
      end
    else
      log.error "no ilm #{ilm}"
    end
    age
  end

  def find_delete_age(index)
    ilm = find_ilm_from_template(index)
    return false unless ilm
    find_delete_age_in_ilm(ilm)
  end

  def find_delete_after(index)
    age = find_delete_age(index)
    return false unless age
    index_date  = Date.parse(index.delete('-'))
    delete_date = index_date + age
    today       = Date.today
    (delete_date - today).to_i
  end

  def create_snapshot(index)
    # prepare snapshot
    # put snapshot
    # wait while snapshot will be created
    # check that snapshod good
  end

  def make_snapshot(index)
    snapshot = get_snapshot(index)
    if snapshot
      delete_snapshot(snapshot) if snapshot_partial?(snapshot)
      return true if snapshot_is_good?(snapshot)
    end
    create_snapshot(index)
  end

  def snapshot
    log.warn 'command snapshot not implemented yet'

    all_indices.each do |index|
      will_delete_after = find_delete_after(index)
      unless will_delete_after
        # SLACK: ERR: can't snapshot index #{index}: can't detect delete date
        next
      end

      if will_delete_after < 0
        log.error "index #{index} should have been deleted by ILM but he is not!"
        # SLACK: ERR: "index #{index} should have been deleted by ILM but he is not!"
        next
      elsif will_delete_after < 7
        unless make_snapshot(index)
          if will_delete_after < 3
            log.error "can't snapshot index #{index} that will be deleted soon"
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

  # def snapshot_populate_indices(indices, date_from, date_to, daysago)
  #   result = []
  #
  #   if indices.length == 1 && indices.first == '_all'
  #     result = @elastic.all_indices(date_from, date_to, daysago, nil, @config['settings']['box_types']['store'], @config)
  #   else
  #     if date_from.nil?
  #       result = @elastic.all_indices(date_from, date_to, daysago, nil, @config['settings']['box_types']['store'], @config).select { |r| r.start_with?(*indices) }
  #     else
  #       date_from.upto(date_to) do |date|
  #         indices.each do |index|
  #           date_formatted = date.to_s.tr('-', '.')
  #           result << "#{index}-#{date_formatted}"
  #         end
  #       end
  #     end
  #   end
  #
  #   return result unless result.empty?
  #
  #   log.fatal 'no indices for work'
  #   exit 1
  # end
  #
  # def do_snapshot(indices)
  #   indices.each do |index|
  #     next if skip_index?(index, 'snapshot')
  #
  #     response = @elastic.request(:get, "/_cat/indices/#{index}")
  #
  #     if index_exist?(response)
  #       elastic_action_with_log('open_index', index) unless already?(response, 'open')
  #       elastic_action_with_log('delete_index', index) if elastic_action_with_log('snapshot_index', index)
  #     else
  #       log.warn "#{index} index not found"
  #     end
  #   end
  # end
  #
  # def snapshot
  #   indices, date_from, date_to, daysago = prepare_vars
  #   prechecks(date_from, date_to)
  #   indices = snapshot_populate_indices(indices, date_from, date_to, daysago)
  #   log.debug indices.inspect
  #   do_snapshot(indices)
  # end
end
