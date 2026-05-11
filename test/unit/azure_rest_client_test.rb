require_relative '../test_plugin_helper'
require 'webmock/minitest'

class AzureRestClientTest < ActiveSupport::TestCase
  setup do
    @base_url = 'https://management.azure.com'
    @token_url = 'https://login.microsoftonline.com/test-tenant/oauth2/v2.0/token'

    stub_request(:post, @token_url).to_return(
      body: { access_token: 'test-token', expires_in: 3600 }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    @client = ForemanAzureRm::AzureRestClient.new(
      tenant: 'test-tenant',
      client_id: 'test-client',
      client_secret: 'test-secret',
      subscription_id: 'test-sub',
      azure_environment: 'azure'
    )
  end

  test "acquires token on first request" do
    stub_request(:get, "#{@base_url}/test?api-version=2023-01-01")
      .to_return(body: { value: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    @client.get('/test', api_version: '2023-01-01')

    assert_requested :post, @token_url, times: 1
  end

  test "reuses cached token" do
    stub_request(:get, "#{@base_url}/test?api-version=2023-01-01")
      .to_return(body: { value: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

    @client.get('/test', api_version: '2023-01-01')
    @client.get('/test', api_version: '2023-01-01')

    assert_requested :post, @token_url, times: 1
  end

  test "wraps JSON response with snake_case OpenStruct" do
    stub_request(:get, "#{@base_url}/test?api-version=2023-01-01")
      .to_return(
        body: { 'displayName' => 'East US', 'vmSize' => 'Standard_A0' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    result = @client.get('/test', api_version: '2023-01-01')

    assert_equal 'East US', result.display_name
    assert_equal 'Standard_A0', result.vm_size
  end

  test "wraps nested JSON with recursive OpenStruct" do
    stub_request(:get, "#{@base_url}/test?api-version=2023-01-01")
      .to_return(
        body: {
          'properties' => {
            'hardwareProfile' => { 'vmSize' => 'Standard_B2s' },
            'storageProfile' => {
              'osDisk' => { 'diskSizeGb' => 30 },
            },
          },
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    result = @client.get('/test', api_version: '2023-01-01')

    assert_equal 'Standard_B2s', result.properties.hardware_profile.vm_size
    assert_equal 30, result.properties.storage_profile.os_disk.disk_size_gb
  end

  test "raises AzureApiError on 4xx/5xx" do
    stub_request(:get, "#{@base_url}/test?api-version=2023-01-01")
      .to_return(
        status: 404,
        body: { error: { code: 'ResourceNotFound', message: 'Not found' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.get('/test', api_version: '2023-01-01')
    end
    assert_equal 404, error.status_code
    assert_match(/Not found/, error.message)
  end

  test "raises on invalid azure environment" do
    assert_raises(ArgumentError) do
      ForemanAzureRm::AzureRestClient.new(
        tenant: 't', client_id: 'c', client_secret: 's',
        subscription_id: 'sub', azure_environment: 'invalid'
      )
    end
  end

  test "serializes OpenStruct body with camelCase keys" do
    stub_request(:put, "#{@base_url}/test?api-version=2023-01-01")
      .with { |req| JSON.parse(req.body)['vmSize'] == 'Standard_A0' }
      .to_return(body: '{}', headers: { 'Content-Type' => 'application/json' })

    body = OpenStruct.new(vm_size: 'Standard_A0')
    @client.put('/test', body, api_version: '2023-01-01')

    assert_requested :put, "#{@base_url}/test?api-version=2023-01-01"
  end
end
