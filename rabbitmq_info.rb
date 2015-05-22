require 'net/http'
require 'uri'
require 'json'
require 'resolv'

RABBIT_HOSTS = %w(cony47-2.mobile.rz cony46-2.mobile.rz bunny46-1.mobile.rz bunny47-1.mobile.rz bunny38-1.mobile.rz cony38-3.mobile.rz)
CONSUMER_API_CALL = '/api/consumers'
SEPERATOR = '==>'
=begin
#TODO
- use erb file to output html
- save to file, entry per line 
curl -u guest:guest http://bunny46-1:15672/api/consumers |python -m json.tool
=end

filename = "rabbitmq.txt"

queue_consumer = Hash.new

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


RABBIT_HOSTS.each do |rabbit|
  
#queue_consumer.each { |q,h|  puts "queue: #{q}, consumers: #{h}"}
#exit!
  response_json = response_body(get("http://#{rabbit}:15672" + CONSUMER_API_CALL,"guest","guest"))
  
  response_json.each do |c|
    queue = c[:queue][:name]
    host = c[:channel_details][:peer_host]
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
