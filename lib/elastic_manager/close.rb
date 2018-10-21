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

  def close
    indices, date_from, date_to = prepare_vars
    prechecks(indices, date_from, date_to)
    indices = all_precheck(indices, date_from, date_to, 'open')

    date_from.upto(date_to) do |date|
      do_close(indices, date.to_s.tr!('-', '.'))
    end
  end
end
