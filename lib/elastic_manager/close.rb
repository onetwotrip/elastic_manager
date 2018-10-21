module Close
  def do_close(indices, date)
    indices.each do |index_name|
      next if skip?('close', index_name)

      index    = "#{index_name}-#{date}"
      response = @elastic.request(:get, "/_cat/indices/#{index}")

      if index_exist?(response)
        next if already?('close', response, index)

        action_with_log('close', index)
      else
        log.warn "#{index} index not found, maybe already snapshoted"
      end
    end
  end
end
