require 'logger'
require 'colorize'

module Logging
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

    def severity_color(severity, message)
      case severity
      when 'DEBUG'
        message.cyan
      when 'INFO'
        message.green
      when 'WARN'
        message.yellow
      when 'ERROR'
        message.light_red
      when 'FATAL'
        message.red
      when 'UNKNOWN'
        message.magenta
      end
    end

    def configure_logger_for(classname)
      logger          = Logger.new(STDOUT)
      logger.progname = classname
      logger.level    = log_level

      logger.formatter = proc do |severity, datetime, progname, msg|
        datetime = datetime.strftime("%Y-%m-%d | %I:%M:%S.%L")
        message  = "#{datetime} | #{progname} | #{severity} | #{msg}\n"
        message  = severity_color(severity, message)
      end

      logger
    end
  end
end
