require 'net/http'
require 'json'
require 'uri'
require 'ostruct'

module ForemanAzureRm
  class AzureRestClient
    AZURE_ENVIRONMENTS = {
      'azure' => {
        ad_login: 'https://login.microsoftonline.com',
        resource_manager: 'https://management.azure.com',
      },
      'azureusgovernment' => {
        ad_login: 'https://login.microsoftonline.us',
        resource_manager: 'https://management.usgovcloudapi.net',
      },
      'azurechina' => {
        ad_login: 'https://login.chinacloudapi.cn',
        resource_manager: 'https://management.chinacloudapi.cn',
      },
      'azuregermancloud' => {
        ad_login: 'https://login.microsoftonline.de',
        resource_manager: 'https://management.microsoftazure.de',
      },
    }

    attr_reader :subscription_id

    def initialize(tenant:, client_id:, client_secret:, subscription_id:, azure_environment: 'azure')
      @tenant = tenant
      @client_id = client_id
      @client_secret = client_secret
      @subscription_id = subscription_id
      env = AZURE_ENVIRONMENTS[azure_environment.downcase]
      raise ArgumentError, "Unknown Azure environment: #{azure_environment}" unless env
      @ad_login_url = env[:ad_login]
      @base_url = env[:resource_manager]
      @token = nil
      @token_expires_at = Time.at(0)
    end

    def get(path, api_version:, params: {})
      request(:get, path, api_version: api_version, params: params)
    end

    def put(path, body, api_version:)
      request(:put, path, api_version: api_version, body: body)
    end

    def post(path, body = nil, api_version:)
      request(:post, path, api_version: api_version, body: body)
    end

    def delete(path, api_version:)
      request(:delete, path, api_version: api_version)
    end

    def get_paged(path, api_version:, params: {})
      results = []
      loop do
        response = get(path, api_version: api_version, params: params)
        items = response.respond_to?(:value) ? response.value : []
        results.concat(items)
        next_link = response.respond_to?(:next_link) ? response.next_link : nil
        break unless next_link
        path = URI.parse(next_link).request_uri
        params = {}
        api_version = nil
      end
      results
    end

    private

    def request(method, path, api_version: nil, params: {}, body: nil)
      ensure_token

      uri = build_uri(path, api_version, params)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 60
      http.read_timeout = 300

      req = build_request(method, uri, body)
      response = http.request(req)

      handle_response(response)
    end

    def build_uri(path, api_version, params)
      url = path.start_with?('http') ? path : "#{@base_url}#{path}"
      uri = URI.parse(url)
      query = URI.decode_www_form(uri.query || '')
      query << ['api-version', api_version] if api_version
      params.each { |k, v| query << [k.to_s, v.to_s] }
      uri.query = URI.encode_www_form(query)
      uri
    end

    def build_request(method, uri, body)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post,
                 put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req['Authorization'] = "Bearer #{@token}"
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req.body = serialize_body(body) if body
      req
    end

    def serialize_body(body)
      case body
      when String then body
      when OpenStruct then deep_camelize_keys(body.to_h).to_json
      when Hash then deep_camelize_keys(body).to_json
      else body.to_json
      end
    end

    def handle_response(response)
      case response
      when Net::HTTPAccepted
        poll_async_operation(response)
      when Net::HTTPSuccess
        return nil if response.body.nil? || response.body.empty?
        json = JSON.parse(response.body)
        wrap_response(json)
      else
        error = begin
                  JSON.parse(response.body)
                rescue StandardError
                  { 'error' => { 'message' => response.body } }
                end
        err = error.dig('error', 'message') || error.dig('error', 'code') || response.message
        raise AzureApiError.new("Azure API error #{response.code}: #{err}", response.code.to_i)
      end
    end

    def poll_async_operation(response)
      poll_url = response['Azure-AsyncOperation'] || response['Location']
      resource_url = response.uri.to_s
      return nil unless poll_url

      loop do
        sleep 2
        uri = URI.parse(poll_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{@token}"
        poll_response = http.request(req)
        poll_json = JSON.parse(poll_response.body)
        status = poll_json['status']
        case status
        when 'Succeeded'
          return request(:get, resource_url)
        when 'Failed', 'Canceled'
          raise AzureApiError.new("Async operation #{status}: #{poll_json.dig('error', 'message')}", 500)
        end
      end
    end

    def ensure_token
      return if @token && Time.now < @token_expires_at - 60

      uri = URI.parse("#{@ad_login_url}/#{@tenant}/oauth2/v2.0/token")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(
        'grant_type' => 'client_credentials',
        'client_id' => @client_id,
        'client_secret' => @client_secret,
        'scope' => "#{@base_url}/.default"
      )
      response = http.request(req)
      unless response.is_a?(Net::HTTPSuccess)
        raise AzureApiError.new("Token acquisition failed: #{response.body}", response.code.to_i)
      end
      token_data = JSON.parse(response.body)
      @token = token_data['access_token']
      @token_expires_at = Time.now + token_data['expires_in'].to_i
    end

    def wrap_response(data)
      case data
      when Hash then deep_to_ostruct(deep_underscore_keys(data))
      when Array then data.map { |item| wrap_response(item) }
      else data
      end
    end

    def deep_to_ostruct(hash)
      converted = hash.transform_values do |v|
        case v
        when Hash then deep_to_ostruct(v)
        when Array then v.map { |item| item.is_a?(Hash) ? deep_to_ostruct(item) : item }
        else v
        end
      end
      OpenStruct.new(converted)
    end

    def deep_underscore_keys(hash)
      hash.each_with_object({}) do |(k, v), result|
        new_key = k.to_s.underscore
        result[new_key] = case v
                          when Hash then deep_underscore_keys(v)
                          when Array then v.map { |item| item.is_a?(Hash) ? deep_underscore_keys(item) : item }
                          else v
                          end
      end
    end

    def deep_camelize_keys(hash)
      hash.each_with_object({}) do |(k, v), result|
        new_key = k.to_s.camelize(:lower)
        result[new_key] = case v
                          when Hash then deep_camelize_keys(v)
                          when Array then v.map { |item| item.is_a?(Hash) ? deep_camelize_keys(item) : item }
                          when OpenStruct then deep_camelize_keys(v.to_h)
                          else v
                          end
      end
    end
  end

  class AzureApiError < StandardError
    attr_reader :status_code

    def initialize(message, status_code = nil)
      super(message)
      @status_code = status_code
    end
  end
end
