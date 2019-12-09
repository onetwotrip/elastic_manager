# frozen_string_literal: true

module Sync
  def sync_ilms
    log.info 'sync ilm'
    elastic_ilm = JSON.parse(@elastic.request(:get, '/_ilm/policy'))
    ilm_for_delete = []
    elastic_ilm.keys.each do |ilm|
      # we can't check reserved ilm, so will process only custom ilm starts with twiket
      # due this any custom ilm must be named with twiket prefix
      next unless ilm.start_with?('twiket')

      if @config['ilms'][ilm]
        if @config['ilms'][ilm].key?('retired') && @config['ilms'][ilm]['retired']
          log.warn "ilm '#{ilm}' retired"
        else
          next
        end
      end
      ilm_for_delete << ilm
    end
    log.info "will delete ilm: #{ilm_for_delete}"

    ilm_for_create = []
    @config['ilms'].each do |ilm, params|
      next if params['retired']
      ilm_for_create << ilm
    end
    log.info "will put ilm: #{ilm_for_create}"

    sleep 3

    ilm_for_delete.each do |ilm|
      res = @elastic.request(:delete, "/_ilm/policy/#{ilm}")
      log.info "delete #{ilm}: #{res}"
    end

    # TODO: (anton.ryabov) mb diff before and put only if changed?
    # elastic will accept each request and increment policy version even if no difference in policies
    # how big number they have for version?
    ilm_for_create.each do |ilm|
      res = @elastic.request(:put, "/_ilm/policy/#{ilm}", @config['ilms'][ilm]['config'])
      log.info "create #{ilm}: #{res}"
    end
  end
end