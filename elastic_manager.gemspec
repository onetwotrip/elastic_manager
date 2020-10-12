# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'elastic_manager'
  s.executables = ['elastic_manager']
  s.version     = '0.3.5'
  s.date        = '2018-10-15'
  s.summary     = 'Because qurator sucks'
  s.description = 'Manager for logstash indices in elastic'
  s.authors     = ['Antony Ryabov']
  s.email       = 'mail@doam.ru'
  s.files       = %w[LICENSE.md README.md elastic_manager.gemspec .ruby-version .ruby-gemset]
  s.files       += Dir['lib/**/*.rb']
  s.homepage    = 'https://github.com/onetwotrip/elastic_manager'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 2.5'
  s.add_dependency 'colorize',  '~> 0.8'
  s.add_dependency 'dotenv',    '~> 2.4'
  s.add_dependency 'http',      '~> 3.3'
  s.add_dependency 'rake',      '>= 12.3', '< 14.0'
  s.add_dependency 'yajl-ruby', '~> 1.4'
end
