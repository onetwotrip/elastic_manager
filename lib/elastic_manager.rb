require 'dotenv/load'
require 'date'
require 'elastic_manager/config'
require 'elastic_manager/logger'
require 'elastic_manager/request'
require 'elastic_manager/utils'
require 'elastic_manager/open'

class ElasticManager
  include Config
  include Logging
  include Request
  include Utils
  include Open

  def initialize(argv)
    if argv.size == 0
      @config = load_from_env
    else
      @config = load_from_argv
    end

    @elastic = Request::Elastic.new(@config)
  end

  def run
    if @config['task'].downcase == 'open'
      open
    end
  end
end
