# frozen_string_literal: true

require 'dotenv/load'
require 'date'
require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/utils'
require 'elastic_manager/open'

# Main
class ElasticManager
  include Config
  include Logging
  include Request
  include Utils
  include Open

  def initialize
    @config = load_from_env

    @elastic = Request::Elastic.new(@config)
  end

  def run
    if @config['task'].casecmp('open').zero?
      open
    end
  end
end
