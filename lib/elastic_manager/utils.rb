require 'json'
require 'yajl'

module Utils
  include Logging

  def true?(obj)
    obj.to_s.downcase == 'true'
  end

  def json_parse(string)
    JSON.parse(string)
  rescue JSON::ParserError => e
    log.fatal "json parse err: '''#{e.message}'''\n\t#{e.backtrace.join("\n\t")}"
    exit 1
  end
end
