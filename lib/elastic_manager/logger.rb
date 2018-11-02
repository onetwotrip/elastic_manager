# frozen_string_literal: true

require 'logger'
require 'colorize'

# Universal global logging
module Logging

  SEVERITY_COLORS = {
    'DEBUG'   => 'cyan',
    'INFO'    => 'green',
    'WARN'    => 'yellow',
    'ERROR'   => 'light_red',
    'FATAL'   => 'red',
    'UNKNOWN' => 'magenta'
  }.freeze

  def log
    @log ||= Logging.logger_for(self.class.name)
  end

  # Use a hash class-ivar to cache a unique Logger per class:
  @loggers = {}

  # Global, memoized, lazy initialized instance of a logger
  class << self
    def logger_for(classname)
      @loggers[classname] ||= configure_logger_for(classname)
    end

    def log_level
      # :debug < :info < :warn < :error < :fatal < :unknown
      if ENV['LOG_LEVEL'] == '' || ENV['LOG_LEVEL'].nil?
        'INFO'
      else
        ENV['LOG_LEVEL']
      end
    end

    def configure_logger_for(classname)
      logger          = Logger.new(STDOUT)
      logger.progname = classname
      logger.level    = log_level

      logger.formatter = proc do |severity, datetime, progname, msg|
        datetime = datetime.strftime('%Y-%m-%d | %I:%M:%S.%L')
        message  = "#{datetime} | #{progname} | #{severity} | #{msg}\n"
        message.send(SEVERITY_COLORS[severity])
      end

      logger
    end
  end
end
