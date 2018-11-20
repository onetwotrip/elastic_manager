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

    def override_daysago(index_name, config, daysago)
      if config['indices'][index_name] &&
         config['indices'][index_name]['daysago'] &&
         config['indices'][index_name]['daysago'][config['task']] &&
         !config['indices'][index_name]['daysago'][config['task']].to_s.empty?
        log.debug config['indices'][index_name]['daysago'][config['task']]
        config['indices'][index_name]['daysago'][config['task']].to_i
      else
        daysago.to_i
      end
    end

    def all_indices_in_snapshots(from=nil, to=nil, daysago=nil, config)
      all_snapshots = get_all_snapshots
      all_snapshots.select! { |snap| snap['status'] == 'SUCCESS' }

      result = []
      all_snapshots.each do |snap|
        begin
          snap_date = Date.parse(snap['id'].delete('-'))
        rescue ArgumentError => e
          log.error "#{e.message} for #{index}"
          next
        end

        index = snap['id'].gsub('snapshot_', '')
        daysago_local = override_daysago(make_index_name(index), config, daysago)

        if from.nil? && snap_date < (Date.today - daysago_local)
          result << CGI.escape(index)
        elsif (from..to).cover? snap_date
          result << CGI.escape(index)
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

    def all_indices(from=nil, to=nil, daysago=nil, state=nil, type=nil, config)
      indices = get_all_indices

      # TODO: (anton.ryabov) next line just for debug purpose, need better handling
      indices.each { |k, v| log.debug "#{k} - #{v.to_json}" unless v['settings'] }

      indices.select! { |_, v| v['state'] == state } if state
      indices.select! { |_, v| v['settings']['index']['routing']['allocation']['require']['box_type'] == type } if type

      result = []
      indices.each do |index, _|
        begin
          index_date = Date.parse(index.delete('-'))
        rescue ArgumentError => e
          log.error "#{e.message} for #{index}"
          next
        end

        daysago_local = override_daysago(make_index_name(index), config, daysago)

        if from.nil? && index_date < (Date.today - daysago_local)
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
      req_params += 'metadata.indices.*.settings.index.routing.allocation.require.box_type'

      response = request(:get, req_path + req_params)

      if response.code == 200
        json_parse(response)['metadata']['indices']
      else
        log.fatal "can't work with all_indices response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def snapshot_exist?(snapshot_name, repo)
      response = request(:get, "/_snapshot/#{repo}/#{snapshot_name}/")

      if response.code == 200
        true
      elsif response.code == 404
        false
      else
        log.fatal "can't check snapshot existing, response was: #{response.code} - #{response}"
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
        snapshot = json_parse(response)['snapshots'][0]

        if snapshot['state'] == 'SUCCESS'
          snapshot['snapshot']
        else
          log.fatal 'wrong snapshot state'
          exit 1
        end
      else
        log.fatal "can't find snapshot #{snapshot_name} in #{repo} response was: #{response.code} - #{response}"
        exit 1
      end
    end

    def restore_snapshot(index, box_type)
      snapshot_name = "snapshot_#{index}"
      snapshot_repo = find_snapshot_repo
      snapshot      = find_snapshot(snapshot_repo, snapshot_name)

      body = {
        index_settings: {
          'index.number_of_replicas'                  => 0,
          'index.refresh_interval'                    => -1,
          'index.routing.allocation.require.box_type' => box_type
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
        return false
      end

      response['acknowledged'].is_a?(TrueClass)
    end

    def close_index(index, tag)
      box_type = index_box_type(index)

      return false if box_type.nil?

      if box_type == tag
        log.fatal "i will not close index #{index} in box_type #{tag}"
        false
      else
        response = request(:post, "/#{index}/_close?master_timeout=1m")

        if response.code == 200
          response = json_parse(response)
        else
          log.fatal "wrong response code for #{index} close"
          return false
        end

        response['acknowledged'].is_a?(TrueClass)
      end
    end

    def index_box_type(index)
      response = request(:get, "/#{index}/_settings/index.routing.allocation.require.box_type")

      if response.code == 200
        response = json_parse(response)
        box_type = response[CGI.unescape(index)]['settings']['index']['routing']['allocation']['require']['box_type']
        log.debug "for #{index} box_type is #{box_type}"
        box_type
      else
        log.fatal "can't check box_type for #{index}, response was: #{response.code} - #{response}"
        nil
      end
    end

    def chill_index(index, box_type)
      body = {
        'index.routing.allocation.require.box_type' => box_type
      }
      response = request(:put, "/#{index}/_settings?master_timeout=1m", body)

      if response.code == 200
        response = json_parse(response)
      else
        log.fatal "can't chill #{index}, response was: #{response.code} - #{response}"
        return false
      end

      response['acknowledged'].is_a?(TrueClass)
    end

    def delete_index(index)
      snapshot_name = "snapshot_#{index}"
      snapshot_repo = find_snapshot_repo

      return false unless find_snapshot(snapshot_repo, snapshot_name)

      response = request(:delete, "/#{index}")

      if response.code == 200
        response = json_parse(response)
      else
        log.fatal "can't delete index #{index}, response was: #{response.code} - #{response}"
        return false
      end

      response['acknowledged'].is_a?(TrueClass)
    end

    def wait_snapshot(snapshot, repo)
      snapshot_ok = false

      until snapshot_ok
        sleep @sleep
        response = request(:get, "/_snapshot/#{repo}/#{snapshot}/_status")

        if response.code == 200
          # TODO: (anton.ryabov) add logging of percent and time ?
          # stats = status['snapshots'][0]['stats']
          # msg = "(#{stats['total_size_in_bytes']/1024/1024/1024}Gb / #{stats['processed_size_in_bytes']/1024/1024/1024}Gb)"
          # puts "Get backup status #{msg}: retry attempt #{attempt_number}; #{total_delay.round} seconds have passed."
          state = json_parse(response)['snapshots'][0]['state']
          log.debug "snapshot check response: #{response.code} - #{response}"

          if state == 'SUCCESS'
            snapshot_ok = true
          elsif %w[FAILED PARTIAL INCOMPATIBLE].include?(state)
            log.fatal "can't snapshot #{snapshot} in #{repo}: #{response.code} - #{response}"
            exit 1
          end
        else
          log.error "can't check snapshot: #{response.code} - #{response}"
        end
      end

      true
    end

    def snapshot_index(index)
      snapshot_name = "snapshot_#{index}"
      snapshot_repo = find_snapshot_repo

      body = {
        'indices'              => index,
        'ignore_unavailable'   => false,
        'include_global_state' => false,
        'partial'              => false
      }

      response = request(:put, "/_snapshot/#{snapshot_repo}/#{snapshot_name}/", body)

      if response.code == 200
        sleep 5
        wait_snapshot(snapshot_name, snapshot_repo)
      else
        log.error "can't snapshot #{index}, response was: #{response.code} - #{response}"
        false
      end
    end

    def delete_snapshot(snapshot, repo)
      response = request(:delete, "/_snapshot/#{repo}/#{snapshot}")

      if response.code == 200
        response = json_parse(response)
      else
        log.fatal "can't delete snapshot #{snapshot}, response was: #{response.code} - #{response}"
        return false
      end

      response['acknowledged'].is_a?(TrueClass)
    end
  end
end
