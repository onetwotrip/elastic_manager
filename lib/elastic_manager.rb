require 'dotenv/load'
require 'date'
require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/utils'

class ElasticManager
  include Config
  include Logging
  include Request
  include Utils

  # attr_reader :config

  def initialize(argv)
    if argv.size == 0
      @config = load_from_env
    else
      @config = load_from_argv(argv)
    end

    @elastic = Request::Elastic.new(@config)
  end

  def work
    if @config['task'].downcase == 'open'
      indices   = @config['indices'].split(',')
      date_from = Date.parse(@config['from'])
      date_to   = Date.parse(@config['to'])

      unless true?(@config['force'])
        unless @elastic.green?
          log.fatal "elasticsearch on #{@config['es']['url']} is not green"
          exit 1
        end
      end

      if indices.length == 1 && indices.first == '_all'
        # indices = es_all_indices(date_from, date_to, 'close')
        indices = @elastic.all_indices(date_from, date_to, 'close')
      end

      date_from.upto(date_to) do |date|
        date = date.to_s.tr!('-', '.')

        indices.each do |index_name|
          if @config['settings'][index_name]
            if @config['settings'][index_name]['skip_open']
              log.debug @config['settings'][index_name]['skip_open'].inspect

              if true?(@config['settings'][index_name]['skip_open'])
                log.warn "#{index_name} index open skiped"
                next
              end
            end
          end

          index = "#{index_name}-#{date}"

          response = @elastic.request(:get, "/_cat/indices/#{index}")

          if response.code == 404
            log.warn "#{index} index not found"
            log.info "#{index} trying snapshot restore"

            if @elastic.restore_snapshot(index)
              log.info "#{index} restored"
            else
              log.error "#{index} troubles with restore"
            end
          elsif response.code == 200
            if response.body.to_s =~ /open/
              log.warn "#{index} index already opened"
              next
            end

            if @elastic.open_index(index)
              log.info "#{index} index open success"
            else
              log.fatal "#{index} index open failed"
              exit 1
            end
          else
            log.fatal "can't work with index #{index} response was: #{response.code} - #{response}"
            exit 1
          end
        end
      end
    end
  end
end
