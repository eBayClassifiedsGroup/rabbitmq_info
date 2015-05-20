require 'net/http'
require 'uri'
require 'json'

RABBIT_HOSTS = %w(cony47-2:15672 cony46-2:15672)
CONSUMER_API_CALL = '/api/consumers'
=begin
#TODO
- use erb file to output html
- save to file, entry per line 
curl -u guest:guest http://bunny46-1:15672/api/consumers |python -m json.tool
=end


puts response_body(get("URL_HERE"))

BEGIN {
  def get(url)
    uri = construct_uri url
    begin
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
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
