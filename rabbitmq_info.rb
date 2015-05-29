#! /usr/bin/env ruby
require 'net/http'
require 'net/ssh'
require 'uri'
require 'json'
require 'resolv'
require 'optparse'
require 'yaml'


VERSION = 1.0
CONSUMER_API_CALL = '/api/consumers'
SEPERATOR = '==>'

=begin
#TODO
- use erb file to output html
- save to file, entry per line 
curl -u guest:guest http://bunny46-1:15672/api/consumers |python -m json.tool
=end

filename = "rabbitmq.txt"
translate = false
config = nil

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.release =  VERSION
  
  opts.on("-v", "--version", "Version info") do |v|
    puts "#{$0} version #{opts.release}"
    exit
  end
  
  opts.on("-t", "--translate", "Default: #{translate}" ) do |t|
    translate = true
  end
  
  opts.on("-c", "--config FILE", "yaml config file" ) do |c|
    config = c
  end
  
end.parse!
  
abort("a yaml config file is required.  See -h for help") if (config.nil?)
  
  abort("config file \'#{config}\' does not exist") unless (File.file?(config)) 
  config_parsed = begin
    YAML.load(File.open(config))
  rescue ArgumentError, Errno::ENOENT => e
    $stderr.puts "Exception while opening yaml config file: #{e}"
    exit!
  end
  
  config_file = Hash.new
  begin
    config_file = config_parsed.inject({}){|h,(k,v)| h[k.to_sym] = v; h}
  rescue NoMethodError => e
    $stderr.puts "error parsing configuration yaml: #{e.message}"
  end


#puts config_file.keys

queue_consumer = Hash.new
connection_map = Hash.new
rabbit_hosts = config_file[:rabbit_hosts]

begin
fhandle = File.open(filename, "r")
    fhandle.readlines.each do |line|
      queue, hosts = line.split(SEPERATOR)
      queue.strip!
      queue_consumer[queue] ||= []
      #puts hosts
      hosts.split(',').each do |h|
        queue_consumer[queue] << h.strip 
      end
  end
rescue Errno::ENOENT
end

def gen_connection(con1, con2)
  c1 = con1.split(/\s+/)
  c2 = con2.split(/\s+/)
  { "srcport" => c2[1].to_i, "srcip" => c1[0] }
end

if (translate)
  # Determine real IP behind a netscaler vserver
  # http://support.citrix.com/article/CTX126853
  config_file.each do |ns, config|
    connection_map[ns] = Array.new()
    Net::SSH.start(ns.to_s, config['username'], :password => config['password']) do |ssh|
      config['vservers'].each do |vserver|
        output = ssh.exec!("show ns connectiontable 'VSVRNAME = " + vserver + "' -detail LINK")
        lines = output.split("\n")
        lines.shift # Done
        lines.pop   # Done
        lines.shift # header
        loop do
          connection_map[ns].push(gen_connection(lines.shift(), lines.shift()))
          break if lines.empty?
        end
      end
    end
  end
end

rabbit_hosts.each do |rabbit|
  
#queue_consumer.each { |q,h|  puts "queue: #{q}, consumers: #{h}"}
#exit!
  response_json = response_body(get("http://#{rabbit}:15672" + CONSUMER_API_CALL,"guest","guest"))
  response_json.each do |c|
    queue = c[:queue][:name]
    host = c[:channel_details][:peer_host]
    port = c[:channel_details][:peer_port]
    
    if (translate) 
      # lookup port in netscaler ouput to replace peer_host
      config_file.each do |ns,config|
        if config['ip']  == host
          cons = connection_map[ns]
          cons.each do |con|
            if con['srcport'] == port
              host = con['srcip']
              break
            end
          end
        end
      end    
    end
    
    begin
      hostname = Resolv.getname(host)
     rescue Resolv::ResolvError
      hostname = host
     end
    (queue_consumer[queue] ||= [] ) << hostname
  end
  
  fout = File.open(filename, "w+")
  
  queue_consumer.keys.sort.each do |q|
    fout.puts "#{q} #{SEPERATOR} #{queue_consumer[q].uniq.join(', ')}"
  end
  
  fout.close
end

queue_consumer.each { |q,h|  puts "queue: #{q}, consumers: #{h.uniq.join(',')}"}
  
BEGIN {
  def get(url,username,password)
    uri = construct_uri url
    begin
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth 'guest', 'guest' unless (username.nil? || password.nil?)
    req["Content-Type"] = "application/json"
    response = http.request(req)
    rescue  Errno::ECONNREFUSED, SocketError => e
      message = "Error calling url #{url}: #{e.message}"
      STDERR.puts(message)
      raise EErrno::ECONNREFUSED, message, caller
    end
    return  response
  end

  def construct_uri(url)
    raise BadURLError unless (valid_url(url))
    return URI.parse(url)
  end

  def valid_url(url)
    if (url =~ /\A#{URI::regexp}\z/)
      return true
    end
    return false
  end
  
  def deep_symbolize(obj)
    return obj.reduce({}) do |memo, (k, v)|
      memo.tap { |m| m[k.to_sym] = deep_symbolize(v) }
    end if obj.is_a? Hash
    
    return obj.reduce([]) do |memo, v| 
      memo << deep_symbolize(v); memo
    end if obj.is_a? Array
  
    obj
  end
  
  def response_body(response)
    if (response.is_a?(Net::HTTPResponse) && !response.body.nil?)
      return deep_symbolize((JSON.parse(response.body)))
    end
    return nil
  end

  class BadURLError < StandardError ; end

}
