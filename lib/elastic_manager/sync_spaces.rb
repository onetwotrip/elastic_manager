# frozen_string_literal: true

module Sync
  def sync_spaces
    log.info 'sync spaces'
    kibana_spaces = JSON.parse(@kibana.request(:get, '/api/spaces/space'))
    spaces_for_delete = []
    kibana_spaces.each do |ks|
      next if ks['_reserved']
      ks_id = ks['id']

      if @config['spaces'][ks_id]
        if @config['spaces'][ks_id].key?('retired') && @config['spaces'][ks_id]['retired']
          log.warn "space '#{ks_id}' retired"
        else
          next
        end
      end
      spaces_for_delete << ks_id
    end
    log.info "will delete spaces: #{spaces_for_delete}"

    spaces_for_create = []
    @config['spaces'].each do |space, params|
      next if params['retired']
      next if kibana_spaces.map { |ks| ks['id'] }.include?(space)
      spaces_for_create << space
    end
    log.info "will put spaces: #{spaces_for_create}"

    sleep 3

    spaces_for_delete.each do |space|
      res = @kibana.request(:delete, "/api/spaces/space/#{space}")
      log.info "delete #{space}: #{res}"
    end

    spaces_for_create.each do |space|
      res = @kibana.request(:post, '/api/spaces/space', @config['spaces'][space]['config'])
      log.info "create #{space}: #{res}"
    end
  end
end