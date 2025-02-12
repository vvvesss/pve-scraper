require 'httparty'
require 'json'

# Proxmox server details

# PROXMOX_URL = 'https://192.168.5.5:8006/api2/json'

# Hashocorp Vault way
# # Read credentials from a Vault secrets file
# begin
#   config_file = '/vault/secrets/config'
#   config_content = File.read(config_file)

#   USERNAME = config_content.match(/export USER="([^"]+)"/)[1]
#   PASSWORD = config_content.match(/export PASS="([^"]+)"/)[1]
# rescue => e
#   puts "Error reading or parsing #{config_file}: #{e.message}"
#   exit 1
# end

#ENV variables way
# Obtain Proxmox server details from environment variables
PROXMOX_URL = ENV['PROXMOX_URL'] || 'https://default-proxmox-url:8006/api2/json'
USERNAME = ENV['USER'] || 'default-user'
PASSWORD = ENV['PASS'] || 'default-password'

def scrape
  # Authenticate with Proxmox
  response = HTTParty.post("#{PROXMOX_URL}/access/ticket", {
    headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
    body: { username: USERNAME, password: PASSWORD },
    verify: false
  })

  return { error: "Unable to authenticate" }.to_json unless response.code == 200

  ticket = response.parsed_response['data']['ticket']
  csrf_token = response.parsed_response['data']['CSRFPreventionToken']

  prometheus_sd_config = []

  # Fetch Proxmox nodes
  nodes = HTTParty.get("#{PROXMOX_URL}/nodes", {
    headers: { 'Cookie' => "PVEAuthCookie=#{ticket}" },
    verify: false
  }).parsed_response['data']

  nodes.each do |node|
    node_name = node['node']

    # Fetch VMs on each node
    vms = HTTParty.get("#{PROXMOX_URL}/nodes/#{node_name}/qemu", {
      headers: { 'Cookie' => "PVEAuthCookie=#{ticket}" },
      verify: false
    }).parsed_response['data']

    vms.each do |vm|
      vmid = vm['vmid']

      # Fetch VM configuration
      config = HTTParty.get("#{PROXMOX_URL}/nodes/#{node_name}/qemu/#{vmid}/config", {
        headers: { 'Cookie' => "PVEAuthCookie=#{ticket}" },
        verify: false
      }).parsed_response['data']

      # Parse VM tags into labels
      tags = (config["tags"] || '').split(';')
      next if tags.include?("skipped")
      
      labels = tags.each_with_object({}) do |tag, hash|
        next unless tag.include?('---')
        key, value = tag.split('---')
        hash[key] = value
      end

      # Fetch network interfaces (Guest Agent required)
      interfaces = HTTParty.get("#{PROXMOX_URL}/nodes/#{node_name}/qemu/#{vmid}/agent/network-get-interfaces", {
        headers: { 'Cookie' => "PVEAuthCookie=#{ticket}" },
        verify: false
      }).parsed_response.dig('data', 'result') || []

      ip_addresses = interfaces.flat_map { |iface|
        iface['ip-addresses']&.select { |ip|
          ip['ip-address-type'] == 'ipv4' && ip['ip-address'].start_with?('192.168.210.')
        }&.map { |ip| ip['ip-address'] }
      }.compact

      targets = ip_addresses.map { |ip| "#{ip}:9100" }

      base_labels = {
        "vm_id" => vmid.to_s,
        "pvehost" => node_name,
        "name" => config['name'],
        "ip" => ip_addresses.first.to_s,
        "instance" => config['name'],
        "exporter" => "node_exporter"
      }.merge(labels)

      prometheus_sd_config << { "targets" => targets, "labels" => base_labels }

      if labels.values.include?('blockchain')
        blockchain_labels = base_labels.merge("exporter" => "blockchain_exporter")
        prometheus_sd_config << { "targets" => ip_addresses.map { |ip| "#{ip}:9110" }, "labels" => blockchain_labels }
      end

      if labels.values.include?('blockchain-secondary')
        blockchain_labels = base_labels.merge("exporter" => "blockchain_secondary_exporter")
        prometheus_sd_config << { "targets" => ip_addresses.map { |ip| "#{ip}:9109" }, "labels" => blockchain_labels }
      end
    end
  end

  prometheus_sd_config.to_json
end

loop do
  scrape_cache = scrape
  File.write('/shared/scraper.output', scrape_cache) rescue puts "Error writing file"
  sleep 60
end
