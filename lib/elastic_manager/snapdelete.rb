# frozen_string_literal: true

require 'elastic_manager/logger'

# Index snapshots deleting operations
module SnapDelete
  include Logging

  def snapdelete_populate_indices(indices, date_from, date_to, daysago)
    result = []

    if indices.length == 1 && indices.first == '_all'
      result = @elastic.all_indices_in_snapshots(date_from, date_to, daysago, @config)
    else
      if date_from.nil?
        result = @elastic.all_indices_in_snapshots(date_from, date_to, daysago, @config).select { |r| r.start_with?(*indices) }
      else
        date_from.upto(date_to) do |date|
          indices.each do |index|
            date_formatted = date.to_s.tr('-', '.')
            result << "#{index}-#{date_formatted}"
          end
        end
      end
    end

    return result unless result.empty?

    log.fatal 'no indices for work'
    exit 1
  end

  def do_snapdelete(indices)
    indices.each do |index|
      next if skip_index?(index, 'snapdelete')

      snapshot_name = "snapshot_#{index}"
      snapshot_repo = @elastic.find_snapshot_repo

      if @elastic.snapshot_exist?(snapshot_name, snapshot_repo)
        elastic_action_with_log('delete_snapshot', snapshot_name, snapshot_repo)
      else
        log.warn "#{index} snapshot #{snapshot_name} not found"
      end
    end
  end

  def snapdelete
    indices, date_from, date_to, daysago = prepare_vars
    prechecks(date_from, date_to)
    indices = snapdelete_populate_indices(indices, date_from, date_to, daysago)
    log.debug indices.inspect
    do_snapdelete(indices)
  end
end
