# frozen_string_literal: true

require 'dotenv/load'
require 'date'
require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/utils'
require 'elastic_manager/open'
require 'elastic_manager/close'
require 'elastic_manager/chill'
require 'elastic_manager/snapshot'
require 'elastic_manager/delete'

# Main
class ElasticManager
  include Config
  include Logging
  include Request
  include Utils
  include Open
  include Close
  include Chill
  include Snapshot
  include Delete

  def initialize
    @config = load_from_env

    @elastic = Request::Elastic.new(@config)
  end

  def run
    if @config['task'].casecmp('open').zero?
      open
    elsif @config['task'].casecmp('close').zero?
      close
    elsif @config['task'].casecmp('chill').zero?
      chill
    elsif @config['task'].casecmp('snapshot').zero?
      snapshot
    elsif @config['task'].casecmp('delete').zero?
      delete
    else
      fail_and_exit('wrong task')
    end
  end
end
