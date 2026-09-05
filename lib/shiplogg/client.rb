require "net/http"
require "json"
require "uri"

module Shiplogg
  # Thin wrapper over the JSON API. Every call returns the parsed body or
  # raises Shiplogg::Error with the server's message. The transport is a
  # callable taking (uri, Net::HTTPRequest) and returning a Net::HTTPResponse,
  # so tests can stub it without touching the network.
  class Client
    USER_AGENT = "shiplogg-cli/#{VERSION}".freeze

    DEFAULT_TRANSPORT = lambda do |uri, request|
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    end

    attr_reader :base_url, :token

    def initialize(base_url:, token:, transport: DEFAULT_TRANSPORT)
      @base_url = base_url.sub(%r{/+\z}, "")
      @token = token
      @transport = transport
    end

    # GET /api/v1/me -> { "handle", "log_url", "projects" => [...], "stats" => {...} }
    def me
      request(Net::HTTP::Get, "/api/v1/me")
    end

    # POST /api/v1/entries -> { "entry" => {...}, "log_url" }
    def create_entry(body:, actor: "human", url: nil, project: nil)
      payload = { source: "cli", body: body, actor: actor }
      payload[:external_url] = url if url
      payload[:project] = project if project
      request(Net::HTTP::Post, "/api/v1/entries", payload)
    end

    private
      def request(klass, path, payload = nil)
        raise Error, "no token; run `shiplogg init` or set SHIPLOGG_TOKEN" if token.nil? || token.empty?

        uri = URI.parse(base_url + path)
        req = klass.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Accept"] = "application/json"
        req["User-Agent"] = USER_AGENT
        if payload
          req["Content-Type"] = "application/json; charset=utf-8"
          req.body = JSON.generate(payload)
        end

        response = begin
          @transport.call(uri, req)
        rescue SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, SocketError => e
          raise Error, "could not reach #{base_url} (#{e.class}: #{e.message})"
        end

        parse(response)
      end

      def parse(response)
        json = begin
          response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

        return json if response.code.to_i.between?(200, 299)

        message = json["error"] || "HTTP #{response.code}"
        details = json["details"]
        if details.is_a?(Hash) && !details.empty?
          message += ": " + details.map { |field, errors| "#{field} #{Array(errors).join(', ')}" }.join("; ")
        end
        raise Error, message
      end
  end
end
