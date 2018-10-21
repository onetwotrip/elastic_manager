module Open
  def do_open(indices, date)
    indices.each do |index_name|
      next if skip?('open', index_name)

      index    = "#{index_name}-#{date}"
      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already?('open', response, index)

        action_with_log('open', index)
      else
        log.warn "#{index} index not found"
        log.info "#{index} trying snapshot restore"

        action_with_log('restore_snapshot', index)
      end
    end
  end
end
