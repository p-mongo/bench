#!/usr/bin/env ruby
require 'rubydns'

INTERFACES = [
	[:udp, "0.0.0.0", 5300],
	[:tcp, "0.0.0.0", 5300],
]

IN = Resolv::DNS::Resource::IN

# Use upstream DNS for name resolution.
UPSTREAM = RubyDNS::Resolver.new([[:udp, "8.8.8.8", 53], [:tcp, "8.8.8.8", 53]])

# Start the RubyDNS server
server = RubyDNS::run_server(INTERFACES) do
        match(%r{test.local}, IN::A) do |transaction|
                transaction.respond!("10.0.0.80")
        end

        # Default DNS handler
        otherwise do |transaction|
                transaction.passthrough!(UPSTREAM)
        end
end

sleep(2)
server.stop
