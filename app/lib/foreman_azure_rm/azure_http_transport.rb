require 'faraday'
require 'faraday/net_http'
require 'uri'

module ForemanAzureRm
  class AzureHttpTransport
    Response = Struct.new(:status, :headers, :body, keyword_init: true) do
      def success?
        (200..299).cover?(status)
      end

      def redirect?
        (300..399).cover?(status)
      end

      def accepted?
        status == 202
      end

      def created?
        status == 201
      end

      def no_content?
        status == 204
      end

      def header(name)
        headers[name] || headers[name.downcase] || headers[name.split('-').map(&:capitalize).join('-')]
      end
    end

    def initialize(proxy_uri: URI.parse(''), ssl_cert_store: nil)
      @proxy_uri = proxy_uri
      @ssl_cert_store = ssl_cert_store
    end

    def request(method:, url:, headers: {}, body: nil, open_timeout: 30, read_timeout: 300)
      uri = URI.parse(url)
      raw = connection_for(uri, open_timeout: open_timeout, read_timeout: read_timeout)
        .run_request(method, uri.request_uri, body, headers)
      to_response(raw)
    end

    private

    def connection_for(uri, open_timeout:, read_timeout:)
      Faraday.new(url: "#{uri.scheme}://#{uri.host}:#{uri.port}") do |faraday|
        faraday.proxy = @proxy_uri.to_s if @proxy_uri.host
        faraday.ssl.cert_store = @ssl_cert_store if @ssl_cert_store
        faraday.options.open_timeout = open_timeout
        faraday.options.timeout = read_timeout
        faraday.adapter :net_http
      end
    end

    def to_response(raw)
      Response.new(status: raw.status.to_i, headers: raw.headers.to_h, body: raw.body)
    end
  end
end
