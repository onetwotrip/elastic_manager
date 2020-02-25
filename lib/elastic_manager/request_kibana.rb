# frozen_string_literal: true

module Request
  class Kibana
    include Logging

    def initialize(elastic_pass)
      @client = HTTP.timeout(
        write:   2,
        connect: 3,
        read:    60
      ).headers(
        'Accept':       'application/json',
        'Content-type': 'application/json',
        'kbn-xsrf':     'reporting'
      ).basic_auth(
        user: 'elastic',
        pass: elastic_pass
      )
      @url = 'http://127.0.0.1:5601'
    end

    def request(method, url, body={})
      uri = @url + url
      log.debug "uri: #{uri}"

      response = @client.request(method, uri, json: body)

      if response.code == 200 || response.code == 204
        response
      else
        raise "bad response: #{response} - #{response.inspect}"
      end
    end
  end
end
