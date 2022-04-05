# frozen_string_literal: true

require 'net/ssh'
require 'vault'

# 1.
# take secret_bootstrap_password from vault
# 2.
# run `echo "secret_bootstrap_password" | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add -x "bootstrap.password"` on chosen elasticsearch server
# 3.
# restart elasticsearch daemon on chosen server
# 4.
# cluster must be at least yellow
# 5.
# export VAULT_URL, VAULT_ROLE_ID, VAULT_SECRET_ID
# 6.
# run ruby bin/initial_setup.rb server_name
# 7.
# restart elasticsearch on chosen server again

server = ARGV[0]

if server == '' || server.nil?
  puts 'Usage: ruby bin/initial_setup.rb server_name'
  exit 127
end
puts "working on '#{server}'"

if server =~ /development/
  env = 'development'
elsif server =~ /infra/
  env = 'infra'
else
  puts 'dunno env ¯\_[ツ]_/¯'
  exit 1
end
puts "in env '#{env}'"
puts '-' * 60

sleep 3

vault_url    = ENV.fetch('VAULT_URL')
vault_role   = ENV.fetch('VAULT_ROLE_ID')
vault_secret = ENV.fetch('VAULT_SECRET_ID')
vault = Vault::Client.new(address: vault_url)
vault.auth.approle(vault_role, vault_secret)
puts 'vault connected'

kv = vault.kv('secret')
bootstrap_config = kv.read("#{env}/elasticsearch/bootstrap")
raise "no bootstrap_config for #{env}" if bootstrap_config.nil?
bootstrap_config = JSON.parse(bootstrap_config.data.to_json)

system_users = kv.read("#{env}/elasticsearch/system_users")
raise "no system_users for #{env}" if system_users.nil?
system_users = JSON.parse(system_users.data.to_json)

host = "#{server}.hosts.twiket.com"

Net::SSH.start(host, nil, forward_agent: true) do |ssh|
  ssh.forward.local(9200, '127.0.0.1', 9200)
  puts 'ssh forwarded'
  puts '-' * 60

  system_users.each do |user, pass|
    next if user == 'elastic'
    cmd = "/usr/bin/curl -kis -u elastic:#{bootstrap_config['password']} -H 'Accept: application/json' -H 'Content-type: application/json' 'https://#{server}:9200/_security/user/#{user}/_password' -d '{\"password\":\"#{pass}\"}'"
    puts user
    puts ssh.exec!(cmd)
    puts '-' * 60
  end

  cmd = "/usr/bin/curl -kis -u elastic:#{bootstrap_config['password']} -H 'Accept: application/json' -H 'Content-type: application/json' 'https://#{server}:9200/_security/user/elastic/_password' -d '{\"password\":\"#{system_users['elastic']}\"}'"
  puts 'elastic'
  puts ssh.exec!(cmd)
  puts '-' * 60
end

