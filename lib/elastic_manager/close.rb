# frozen_string_literal: true

require 'elastic_manager/logger'

# Index closing operations
module Close
  include Logging

  def close
    indices, date_from, date_to, daysago = prepare_vars
  end
end
