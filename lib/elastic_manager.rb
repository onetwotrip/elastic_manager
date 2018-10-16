require 'dotenv/load'
require 'date'
require 'http'
require 'elastic_manager/config'
require 'elastic_manager/logger'

class ElasticManager

  include Config
  include Logging

  attr_reader :config

  def initialize(argv)
    if argv.size == 0
      @config = load_from_env
    else
      @config = load_from_argv(argv)
    end
  end

  def true?(obj)
    obj.to_s.downcase == 'true'
  end

  def es_request(verb, uri, json = {})
    tries ||= @config['retry'].to_i

    request_uri = "#{@config['es']['url']}#{uri}"

    response = HTTP.timeout(
                write:   @config['timeout']['write'].to_i,
                connect: @config['timeout']['connect'].to_i,
                read:    @config['timeout']['read'].to_i
              ).headers(
                'Accept':       'application/json',
                'Content-type': 'application/json'
              ).request(
                verb.to_sym,
                request_uri,
                json: json
              )

    if response.code == 200 || response.code == 404
      # TODO (anton.raybov): mb we need to return only one value but empty if 404???
      return response.code, response.body.to_s
    else
      log.fatal "error in request - url: #{request_uri}, status: #{response.code}, response: #{response.body}"
      exit 1
    end

  rescue StandardError => e

    log.warn "try #{tries + 1} '''#{e.message}''' sleeping #{@config['sleep']} sec..."
    sleep @config['sleep'].to_i

    retry unless (tries -= 1).zero?
    abort "backtrace:\n\t#{e.backtrace.join("\n\t")}".red
  end

  def es_green?
    status, response = es_request('get', '/_cluster/health')
    return JSON.parse(response)['status'] == 'green' if status == 200
    false
  end

  def es_all_indices(from=nil, to=nil, state=nil, type=nil)
    req_path   =  '/_cluster/state/metadata/'
    req_params =  '?filter_path=metadata.indices.*.state,'
    req_params << 'metadata.indices.*.settings.index.routing.allocation.require.box_type'

    status, response = es_request('get', req_path + req_params)
    if status == 200
      indices = JSON.parse(response)['metadata']['indices']
    else
      log.fatal "can't work with all_indices response was: #{status} - #{response}"
      exit 1
    end

    indices.select!{ |k, v| v['state'] == state } if state

    if type
      # TODO (anton.ryabov): next line just for debug purpose, need better handling
      indices.each { |k, v| log.warn "#{k} - #{v.to_json}" unless v['settings'] }
      indices.select!{ |k, v| v['settings']['index']['routing']['allocation']['require']['box_type'] == type }
    end

    res = []
    indices.each_key do |index|
      begin
        index_date = Date.parse(index.gsub('-', ''))
      rescue ArgumentError => e
        log.error "#{e.message} for #{index}"
        next
      end

      res << URI.escape(index) if (from..to).cover? index_date
    end

    res
  end

  def work
    if @config['task'].downcase == 'open'
      indices   = @config['indices'].split(',')
      date_from = Date.parse(@config['from'])
      date_to   = Date.parse(@config['to'])

      unless true?(@config['force'])
        unless es_green?
          log.fatal "elasticsearch on #{@config['es']['url']} is not green"
          exit 1
        end
      end

      if indices.length == 1 && indices.first == '_all'
        indices = es_all_indices(date_from, date_to, 'close')
      end

      date_from.upto(date_to) do |date|
        date = date.to_s.tr!('-', '.')

        indices.each do |index_name|
          if @config['skip']['open'].include?(index_name)
            log.warn "#{index_name} index open skiped"
            next
          end

          index = "#{index_name}-#{date}"

          status, response = es_request('get', "/_cat/indices/#{index}")
          if status == 404
            log.warn "#{index} index not found"
            log.info "#{index} trying snapshot restore"

            snapshot_name = "snapshot_#{index}"

            # TODO: we need improve this if several snapshot repos used in elastic
            status, response = es_request('get', '/_snapshot/')
            if status == 200
              snapshot_repo = JSON.parse(response).keys.first

              status, response = es_request('get', "/_snapshot/#{snapshot_repo}/#{snapshot_name}/")
              if status == 200
                snapshot = JSON.parse(response)['snapshots']
                if snapshot.size == 1
                  body = {
                    index_settings: {
                      'index.number_of_replicas'                  => 0,
                      'index.refresh_interval'                    => -1,
                      'index.routing.allocation.require.box_type' => 'warm'
                    }
                  }
                  status, response = es_request('post', "/_snapshot/#{snapshot_repo}/#{snapshot.first['snapshot']}/_restore", body)

                  if status == 200
                    sleep 5
                    restore_ok = false
                    until restore_ok
                      sleep 30
                      status, response = es_request('get', "/#{index}/_recovery")

                      # TODO: add logging of percent and time ?
                      restore_ok = JSON.parse(response)[index]['shards'].map { |s| s['stage'] == 'DONE' }.all?{ |a| a == true }
                    end
                    log.info "#{index} restored"
                  else
                    log.fatal "can't restore snapshot response was: #{status} - #{response}"
                    exit 1
                  end
                else
                  log.fatal "wrong snapshot size"
                  exit 1
                end
              else
                log.fatal "can't work with snapshot response was: #{status} - #{response}"
                exit 1
              end
            else
              log.fatal "can't work with snapshot response was: #{status} - #{response}"
              exit 1
            end
          elsif status == 200
            if response =~ /open/
              log.warn "#{index} index already opened"
              next
            end

            begin
              status, response = es_request('post', "/#{index}/_open?master_timeout=3m")
              if status == 200
                response = JSON.parse(response)
              else
                log.fatal "wrong response code for #{index} open"
                exit 1
              end
            rescue JSON::ParserError => e
              log.fatal "json parse err: '''#{e.message}'''\n\t#{e.backtrace.join("\n\t")}"
              exit 1
            end

            if response['acknowledged'] == true
              log.info "#{index} index open success"
            else
              log.fatal "#{index} index open failed"
              exit 1
            end
          end
        end
      end
    end
  end
end
