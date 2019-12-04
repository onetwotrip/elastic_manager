# frozen_string_literal: true

module Request
  class Error < StandardError; end
  class Throttling < Error; end
  class ServerError < Error; end

  # Elasticsearch requests wrapper
  class Elastic
    include Logging
    include Utils

    RETRY_ERRORS = [StandardError, RuntimeError, Throttling].freeze

    def initialize(elastic_pass)
      @client = HTTP.timeout(
        write:   2,
        connect: 3,
        read:    120
      ).headers(
        'Accept':       'application/json',
        'Content-type': 'application/json'
      ).basic_auth(
        user: 'elastic',
        pass: elastic_pass
      )
      @url   = 'https://127.0.0.1:9200'
      @retry = 10
      @sleep = 30
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

      # Prepare ssl context for requests ... WTF?
      # TODO: (anton.ryabov) mb make changes in http gem for https://github.com/httprb/http/issues/309 ?
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE

      with_retry do
        response = @client.request(method, uri, json: body, ssl_context: ctx)

        if response.code == 503
          raise Request::Throttling.new(response)
        elsif response.status.server_error?
          raise Request::ServerError.new(response)
        end

        response
      end
    end
  end
end
