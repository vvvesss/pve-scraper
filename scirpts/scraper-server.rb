require 'json'
require 'socket'

# Open the file in read mode and load the content into scrape_cache
sleep 30

def readscrape
  file_path = '/shared/scraper.output'
  begin
    # Reading the file content
    scrape_cache = File.read(file_path)
    #puts "File content loaded into scrape_cache successfully."
    return scrape_cache
  rescue Errno::ENOENT
    puts "File not found: #{file_path}"
    return "File not found: #{file_path}"
  rescue => e
    puts "An error occurred: #{e.message}"
    return "An error occurred: #{e.message}"
  end
end

# Setup TCP server to serve the JSON data
server = TCPServer.new("0.0.0.0", 9108)

puts "Server running on port 9108..."

while session = server.accept
  puts "HTTP call from #{session.peeraddr[2]}"
  response_body = readscrape
  response_headers = [
    "HTTP/1.1 200 OK",
    "Content-Type: application/json",
    "Content-Length: #{response_body.bytesize}",
    "Connection: close"
  ]

  session.write response_headers.join("\r\n") + "\r\n\r\n"
  session.write response_body
end
