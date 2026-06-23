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

  test "polls async operation on 202 Accepted and returns resource" do
    resource_url = "#{@base_url}/subscriptions/test-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm?api-version=2024-07-01"
    poll_url = "#{@base_url}/subscriptions/test-sub/providers/Microsoft.Compute/locations/eastus/operations/op-123?api-version=2024-07-01"

    stub_request(:put, resource_url)
      .to_return(
        status: 202,
        headers: { 'Azure-AsyncOperation' => poll_url, 'Location' => resource_url }
      )

    stub_request(:get, poll_url)
      .to_return(
        { body: { status: 'InProgress' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { body: { status: 'Succeeded' }.to_json, headers: { 'Content-Type' => 'application/json' } }
      )

    stub_request(:get, resource_url)
      .to_return(body: { name: 'test-vm', location: 'eastus' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = @client.put(resource_url, { name: 'test-vm' }, api_version: nil)

    assert_equal 'test-vm', result.name
    assert_equal 'eastus', result.location
    assert_requested :get, poll_url, times: 2
  end

  test "raises AzureApiError on async poll failure" do
    resource_url = "#{@base_url}/test?api-version=2023-01-01"
    poll_url = "#{@base_url}/operations/op-456"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(
        body: { status: 'Failed', error: { message: 'Quota exceeded' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.put(resource_url, {}, api_version: nil)
    end
    assert_match(/Failed/, error.message)
    assert_match(/Quota exceeded/, error.message)
  end

  test "raises AzureApiError on poll HTTP error" do
    resource_url = "#{@base_url}/test?api-version=2023-01-01"
    poll_url = "#{@base_url}/operations/op-789"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(status: 500, body: 'Internal Server Error')

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.put(resource_url, {}, api_version: nil)
    end
    assert_equal 500, error.status_code
  end

  test "polls async operation on 201 Created with Azure-AsyncOperation header" do
    resource_url = "#{@base_url}/subscriptions/test-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm?api-version=2023-03-01"
    poll_url = "#{@base_url}/subscriptions/test-sub/providers/Microsoft.Compute/locations/eastus/operations/op-201"

    stub_request(:put, resource_url)
      .to_return(
        status: 201,
        body: { 'name' => 'test-vm', 'properties' => { 'provisioningState' => 'Creating' } }.to_json,
        headers: { 'Azure-AsyncOperation' => poll_url, 'Content-Type' => 'application/json' }
      )

    stub_request(:get, poll_url)
      .to_return(body: { status: 'Succeeded' }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, resource_url)
      .to_return(
        body: { 'name' => 'test-vm', 'location' => 'eastus', 'properties' => { 'provisioningState' => 'Succeeded' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    result = @client.put(resource_url, { name: 'test-vm' }, api_version: nil)

    assert_equal 'test-vm', result.name
    assert_equal 'eastus', result.location
    assert_requested :get, poll_url, times: 1
    assert_requested :get, resource_url, times: 1
  end

  test "async delete does not GET the deleted resource" do
    resource_url = "#{@base_url}/subscriptions/test-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm?api-version=2023-03-01"
    poll_url = "#{@base_url}/subscriptions/test-sub/providers/Microsoft.Compute/locations/eastus/operations/op-del"

    stub_request(:delete, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(body: { status: 'Succeeded' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = @client.delete(resource_url, api_version: nil)

    assert_nil result
    assert_requested :get, poll_url, times: 1
    assert_not_requested :get, resource_url
  end

  test "follows HTTP redirects" do
    original_url = "#{@base_url}/old-path?api-version=2023-01-01"
    redirect_url = "#{@base_url}/new-path?api-version=2023-01-01"

    stub_request(:get, original_url)
      .to_return(status: 301, headers: { 'Location' => redirect_url })

    stub_request(:get, redirect_url)
      .to_return(body: { name: 'redirected' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = @client.get('/old-path', api_version: '2023-01-01')

    assert_equal 'redirected', result.name
    assert_requested :get, redirect_url
  end

  test "polls Location-style async operation (202 then 200)" do
    resource_url = "#{@base_url}/subscriptions/test-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm?api-version=2024-07-01"
    location_url = "#{@base_url}/subscriptions/test-sub/providers/Microsoft.Compute/locations/eastus/operations/op-loc?monitor=true"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Location' => location_url })

    stub_request(:get, location_url)
      .to_return(
        { status: 202, headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: { 'name' => 'test-vm', 'location' => 'eastus' }.to_json, headers: { 'Content-Type' => 'application/json' } }
      )

    result = @client.put(resource_url, { name: 'test-vm' }, api_version: nil)

    assert_equal 'test-vm', result.name
    assert_requested :get, location_url, times: 2
  end

  test "paginates with get_paged" do
    page1_url = "#{@base_url}/items?api-version=2023-01-01"
    page2_url = "#{@base_url}/items?api-version=2023-01-01&skipToken=abc"

    stub_request(:get, page1_url)
      .to_return(
        body: { value: [{ name: 'item1' }], nextLink: page2_url }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, page2_url)
      .to_return(
        body: { value: [{ name: 'item2' }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    results = @client.get_paged('/items', api_version: '2023-01-01')

    assert_equal 2, results.length
    assert_equal 'item1', results[0].name
    assert_equal 'item2', results[1].name
  end

  test "raises AzureApiError when final GET after async Succeeded returns non-2xx" do
    resource_url = "#{@base_url}/subscriptions/test-sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/test-vm?api-version=2023-03-01"
    poll_url = "#{@base_url}/subscriptions/test-sub/providers/Microsoft.Compute/locations/eastus/operations/op-gone"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(body: { status: 'Succeeded' }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, resource_url)
      .to_return(status: 404, body: { error: { code: 'ResourceNotFound', message: 'Not found' } }.to_json)

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.put(resource_url, { name: 'test-vm' }, api_version: nil)
    end
    assert_equal 404, error.status_code
    assert_match(/Final resource fetch failed/, error.message)
  end

  test "raises AzureApiError on non-JSON async poll body instead of timing out" do
    resource_url = "#{@base_url}/test?api-version=2023-01-01"
    poll_url = "#{@base_url}/operations/op-bad-json"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(body: '<html>Bad Gateway</html>', headers: { 'Content-Type' => 'text/html' })

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.put(resource_url, {}, api_version: nil)
    end
    assert_match(/non-JSON/, error.message)
  end

  test "raises AzureApiError when poll response is missing status field" do
    resource_url = "#{@base_url}/test?api-version=2023-01-01"
    poll_url = "#{@base_url}/operations/op-no-status"

    stub_request(:put, resource_url)
      .to_return(status: 202, headers: { 'Azure-AsyncOperation' => poll_url })

    stub_request(:get, poll_url)
      .to_return(body: { result: 'ok' }.to_json, headers: { 'Content-Type' => 'application/json' })

    error = assert_raises(ForemanAzureRm::AzureApiError) do
      @client.put(resource_url, {}, api_version: nil)
    end
    assert_match(/missing 'status'/, error.message)
  end

  test "handles null value in paginated response" do
    stub_request(:get, "#{@base_url}/items?api-version=2023-01-01")
      .to_return(
        body: { value: nil }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    results = @client.get_paged('/items', api_version: '2023-01-01')

    assert_empty results
  end
end
