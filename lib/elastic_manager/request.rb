# frozen_string_literal: true

require 'http'
require 'yajl'
require 'cgi'
require 'elastic_manager/logger'
require 'elastic_manager/request_elastic'
require 'elastic_manager/request_kibana'


# All kind of requests
module Request; end