# frozen_string_literal: true
require 'http'

# Log to Slack
module LogToSlack

  def log_to_slack(text, icon_emoji=nil, username='elastic_manager', channel='#ops')
    if @config['slack'] &&
      @config['slack']['webhook_url'] &&
      @config['slack']['webhook_url'] != ''
      webhook_url = @config['slack']['webhook_url']
    else
      log.error "can't send message to Slack, no slack.webhook_url in vault"
      return false
    end

    body = { text: text }
    body['username']   = username
    body['channel']    = channel
    body['icon_emoji'] = icon_emoji if icon_emoji

    begin
      r = HTTP.timeout(connect: 60, read: 60, write: 60)
              .headers(accept: 'application/json')
              .post(webhook_url, json: body)
      r.status.code == 200
    rescue StandardError => e
      log.error "can't send message to Slack, #{e}"
      false
    end
  end
end