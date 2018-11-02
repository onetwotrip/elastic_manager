# frozen_string_literal: true

require 'http'
require 'yajl'
require 'elastic_manager/logger'
require 'elastic_manager/utils'
require 'cgi'

# All kind of requests
module Request
  class Error < StandardError; end
  class Throttling < Error; end
  class ServerError < Error; end

  # Elasticsearch requests wrapper
  class Elastic
    include Logging
    include Utils

    RETRY_ERRORS = [StandardError, RuntimeError, Throttling].freeze

    def initialize(config)
      @client = HTTP.timeout(
        write:   config['timeout']['write'].to_i,
        connect: config['timeout']['connect'].to_i,
        read:    config['timeout']['read'].to_i
      ).headers(
        'Accept':       'application/json',
        'Content-type': 'application/json'
      )
      @url   = config['es']['url']
      @retry = config['retry'].to_i
      @sleep = config['sleep'].to_i
    end

    def with_retry
      tries ||= @retry

      yield

    rescue *RETRY_ERRORS => e
      log.warn "tries left #{tries + 1} '''#{e.message}''' sleeping #{@sleep} sec..."
      sleep @sleep

      retry unless (tries -= 1).zero?
      log.fatal "backtrace:\n\t#{e.backtrace.join("\n\t")}"
      exit 1
    end

    def request(method, url, body={})
      uri = @url + url
      log.debug "uri: #{uri}"

      with_retry do
        response = @client.request(method, uri, json: body)

        if response.code == 503
          raise Request::Throttling.new(response)
        elsif response.status.server_error?
          raise Request::ServerError.new(response)
        end

        response
      end
    end

    def green?
      response = request(:get, '/_cluster/health')
      return json_parse(response)['status'] == 'green' if response.code == 200

      false
    end

    def all_indices_in_snapshots(from=nil, to=nil, daysago=nil)
      all_snapshots = get_all_snapshots
      all_snapshots.select! { |snap| snap['status'] == 'SUCCESS' }

      result = []
      all_snapshots.each do |snap|
        begin
          snap_date = Date.parse(snap['id'].gsub('-', ''))
        rescue ArgumentError => e
          log.error "#{e.message} for #{index}"
          next
        end

        if from.nil? && snap_date < (Date.today - daysago)
          result << CGI.escape(snap['id'].gsub('snapshot_', ''))
        elsif (from..to).cover? snap_date
          result << CGI.escape(snap['id'].gsub('snapshot_', ''))
        end
      end

      result
    end

    def get_all_snapshots
      snapshot_repo = find_snapshot_repo
      response = request(:get, "/_cat/snapshots/#{snapshot_repo}")

      if response.code == 200
        json_parse(response)
      else
        log.fatal "can't work with all_snapshots response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def all_indices(from=nil, to=nil, daysago=nil, state=nil, type=nil)
      indices = get_all_indices

      # TODO: (anton.ryabov) next line just for debug purpose, need better handling
      indices.each { |k, v| log.debug "#{k} - #{v.to_json}" unless v['settings'] }

      indices.select! { |_, v| v['state'] == state } if state
      indices.select! { |_, v| v['settings']['index']['routing']['allocation']['require']['box_type'] == type } if type

      result = []
      indices.each do |index, _|
        begin
          index_date = Date.parse(index.gsub('-', ''))
        rescue ArgumentError => e
          log.error "#{e.message} for #{index}"
          next
        end

        if from.nil? && index_date < (Date.today - daysago)
          result << CGI.escape(index)
        elsif (from..to).cover? index_date
          result << CGI.escape(index)
        end
      end

      result
    end

    def get_all_indices
      req_path   =  '/_cluster/state/metadata/'
      req_params =  '?filter_path=metadata.indices.*.state,'
      req_params << 'metadata.indices.*.settings.index.routing.allocation.require.box_type'

      response = request(:get, req_path + req_params)

      if response.code == 200
        json_parse(response)['metadata']['indices']
      else
        log.fatal "can't work with all_indices response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def find_snapshot_repo
      # TODO: we need improve this if several snapshot repos used in elastic
      response = request(:get, '/_snapshot/')

      if response.code == 200
        json_parse(response).keys.first
      else
        log.fatal "dunno what to do with: #{response.code} - #{response}"
        exit 1
      end
    end

    def find_snapshot(repo, snapshot_name)
      response = request(:get, "/_snapshot/#{repo}/#{snapshot_name}/")

      if response.code == 200
        snapshot = json_parse(response)['snapshots']

        if snapshot.size == 1
          snapshot.first['snapshot']
        else
          log.fatal "wrong snapshot size"
          exit 1
        end
      else
        log.fatal "can't find snapshot #{snapshot_name} in #{repo} response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def restore_snapshot(index)
      snapshot_name = "snapshot_#{index}"
      snapshot_repo = find_snapshot_repo
      snapshot      = find_snapshot(snapshot_repo, snapshot_name)

      body = {
        index_settings: {
          'index.number_of_replicas'                  => 0,
          'index.refresh_interval'                    => -1,
          'index.routing.allocation.require.box_type' => 'warm'
        }
      }
      response = request(:post, "/_snapshot/#{snapshot_repo}/#{snapshot}/_restore", body)

      if response.code == 200
        sleep 5
        wait_snapshot_restore(index)
      else
        log.fatal "can't restore snapshot #{snapshot_name} response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def wait_snapshot_restore(index)
      restore_ok = false

      until restore_ok
        sleep @sleep / 2
        response = request(:get, "/#{index}/_recovery")

        if response.code == 200
          # TODO: (anton.ryabov) add logging of percent and time ?
          restore_ok = json_parse(response)[index]['shards'].map { |s| s['stage'] == 'DONE' }.all?{ |a| a == true }
        else
          log.error "can't check recovery: #{response.code} - #{response}"
        end
      end

      true
    end

    def open_index(index)
      response = request(:post, "/#{index}/_open?master_timeout=1m")

      if response.code == 200
        response = json_parse(response)
      else
        log.fatal "wrong response code for #{index} open"
        exit 1
      end

      response['acknowledged'].true?
    end
  end
end
