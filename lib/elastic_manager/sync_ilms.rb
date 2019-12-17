# frozen_string_literal: true

module Sync

  def start_ilm
    res = @elastic.request(:get, '/_ilm/status')

    if res.code == 200
      status = JSON.parse(res)['operation_mode']
    else
      log.error "can't start ILM: #{res}"
      exit 1
    end

    if status != 'RUNNING'
      res = @elastic.request(:post, '/_ilm/start')
      if res.code == 200
        log.info 'started ILM'
      else
        log.error "can't start ILM: #{res}"
        exit 1
      end
    end
  end

  def check_and_retry_ilm_errors
    res = @elastic.request(:get, '/_all/_ilm/explain')
    if res.code == 200
      res = JSON.parse(res)['indices']
    else
      log.error "can't get ILM explain"
      exit 1
    end

    failed_indices = []
    res.each do |k, v|
      failed_indices << k if v['step'] == 'ERROR'
    end

    failed_indices.each do |index|
      res = @elastic.request(:post, "/#{index}/_ilm/retry")
      if res.code == 200
        log.info "ILM for '#{index}' retry"
      else
        log.error "failed to retry ILM for '#{index}'"
      end
    end
  end

  def sync_ilms
    log.info 'sync ilm'
    start_ilm
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

    check_and_retry_ilm_errors
  end
end