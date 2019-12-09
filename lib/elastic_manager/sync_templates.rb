# frozen_string_literal: true

module Sync
  def sync_templates
    # 101-200 - 1 shards
    # 201-300 - 2 shards
    # 401-500 - 4 shards
    # 601-700 - 6 shards

    log.info 'sync template'
    elastic_template = JSON.parse(@elastic.request(:get, '/_template'))
    template_for_delete = []
    elastic_template.keys.each do |template|
      # we can't check reserved template, so will process only custom template starts with twiket
      # due this any custom template must be named with twiket prefix
      next unless template.start_with?('twiket')

      if @config['templates'][template]
        if @config['templates'][template].key?('retired') && @config['templates'][template]['retired']
          log.warn "template '#{template}' retired"
        else
          next
        end
      end
      template_for_delete << template
    end
    log.info "will delete template: #{template_for_delete}"

    template_for_create = []
    @config['templates'].each do |template, params|
      next if params['retired']
      template_for_create << template
    end
    log.info "will put template: #{template_for_create}"

    sleep 3

    template_for_delete.each do |template|
      res = @elastic.request(:delete, "/_template/#{template}")
      log.info "delete #{template}: #{res}"
    end

    # TODO: (anton.ryabov) mb diff before and put only if changed?
    # template must have index patterns
    template_for_create.each do |template|
      res = @elastic.request(:put, "/_template/#{template}", @config['templates'][template]['config'])
      log.info "create #{template}: #{res}"
    end
  end
end