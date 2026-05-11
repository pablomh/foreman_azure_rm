module ForemanAzureRm
  class AzureSdkAdapter
    API_VERSIONS = {
      compute: '2023-03-01',
      disks: '2023-02-02',
      network: '2023-04-01',
      storage: '2023-01-01',
      resources: '2021-04-01',
      subscriptions: '2022-12-01',
    }

    def initialize(tenant, app_ident, secret_key, sub_id, azure_environment)
      @sub_id = sub_id
      @client = AzureRestClient.new(
        tenant: tenant,
        client_id: app_ident,
        client_secret: secret_key,
        subscription_id: sub_id,
        azure_environment: azure_environment
      )
    end

    def list_regions(subscription_id)
      @client.get("/subscriptions/#{subscription_id}/locations", api_version: API_VERSIONS[:subscriptions])
    end

    def list_resources(filter)
      @client.get_paged(sub_path('resources'), api_version: API_VERSIONS[:resources], params: { '$filter' => filter })
    end

    def rgs
      @client.get_paged(sub_path('resourcegroups'), api_version: API_VERSIONS[:resources]).map(&:name)
    end

    def vnets
      @client.get_paged(provider_path('Microsoft.Network', 'virtualNetworks'), api_version: API_VERSIONS[:network])
    end

    def subnets(rg_name, vnet_name)
      @client.get_paged(rg_provider_path(rg_name, 'Microsoft.Network', "virtualNetworks/#{vnet_name}/subnets"), api_version: API_VERSIONS[:network])
    end

    def public_ip(rg_name, pip_name)
      network_get(rg_name, "publicIPAddresses/#{pip_name}")
    end

    def vm_nic(rg_name, nic_name)
      network_get(rg_name, "networkInterfaces/#{nic_name}")
    end

    def vm_disk(rg_name, disk_name)
      @client.get(rg_provider_path(rg_name, 'Microsoft.Compute', "disks/#{disk_name}"), api_version: API_VERSIONS[:disks])
    end

    def get_vm_extension(rg_name, vm_name, vm_extension_name)
      compute_get(rg_name, "virtualMachines/#{vm_name}/extensions/#{vm_extension_name}")
    end

    def list_vm_sizes(region)
      return [] if region.blank?
      stripped_region = region.gsub(/\s+/, '').downcase
      response = @client.get(provider_path('Microsoft.Compute', "locations/#{stripped_region}/vmSizes"), api_version: API_VERSIONS[:compute])
      response.value || []
    end

    def list_vms(region)
      @client.get_paged(provider_path('Microsoft.Compute', 'virtualMachines'), api_version: API_VERSIONS[:compute], params: { '$filter' => "location eq '#{region}'" })
    end

    def get_vm(rg_name, vm_name)
      compute_get(rg_name, "virtualMachines/#{vm_name}")
    end

    def get_marketplace_image(location, publisher_name, offer, skus, version)
      @client.get(provider_path('Microsoft.Compute',
        "locations/#{location}/publishers/#{publisher_name}/artifacttypes/vmimage/offers/#{offer}/skus/#{skus}/versions/#{version}"),
        api_version: API_VERSIONS[:compute])
    end

    def list_versions(location, publisher_name, offer, skus)
      @client.get_paged(provider_path('Microsoft.Compute',
        "locations/#{location}/publishers/#{publisher_name}/artifacttypes/vmimage/offers/#{offer}/skus/#{skus}/versions"),
        api_version: API_VERSIONS[:compute])
    end

    def list_custom_images
      @client.get_paged(provider_path('Microsoft.Compute', 'images'), api_version: API_VERSIONS[:compute])
    end

    def get_custom_image(rg_name, image_name)
      compute_get(rg_name, "images/#{image_name}")
    end

    def list_galleries
      @client.get_paged(provider_path('Microsoft.Compute', 'galleries'), api_version: API_VERSIONS[:compute])
    end

    def list_gallery_images(rg_name, gallery_name)
      @client.get_paged(rg_provider_path(rg_name, 'Microsoft.Compute', "galleries/#{gallery_name}/images"), api_version: API_VERSIONS[:compute])
    end

    def get_gallery_image(rg_name, gallery_name, gallery_image_name)
      compute_get(rg_name, "galleries/#{gallery_name}/images/#{gallery_image_name}")
    end

    def list_gallery_image_versions(rg_name, gallery_name, gallery_image_name)
      @client.get_paged(rg_provider_path(rg_name, 'Microsoft.Compute', "galleries/#{gallery_name}/images/#{gallery_image_name}/versions"), api_version: API_VERSIONS[:compute])
    end

    def get_storage_accts
      response = @client.get(provider_path('Microsoft.Storage', 'storageAccounts'), api_version: API_VERSIONS[:storage])
      response.value || []
    end

    def create_or_update_vm(rg_name, vm_name, parameters)
      compute_put(rg_name, "virtualMachines/#{vm_name}", parameters)
    end

    def create_or_update_vm_extensions(rg_name, vm_name, vm_extension_name, extension_params)
      compute_put(rg_name, "virtualMachines/#{vm_name}/extensions/#{vm_extension_name}", extension_params)
    end

    def create_or_update_pip(rg_name, pip_name, parameters)
      network_put(rg_name, "publicIPAddresses/#{pip_name}", parameters)
    end

    def create_or_update_nic(rg_name, nic_name, parameters)
      network_put(rg_name, "networkInterfaces/#{nic_name}", parameters)
    end

    def delete_pip(rg_name, pip_name)
      network_delete(rg_name, "publicIPAddresses/#{pip_name}")
    end

    def delete_nic(rg_name, nic_name)
      network_delete(rg_name, "networkInterfaces/#{nic_name}")
    end

    def delete_vm(rg_name, vm_name)
      compute_delete(rg_name, "virtualMachines/#{vm_name}")
    end

    def delete_disk(rg_name, disk_name)
      @client.delete(rg_provider_path(rg_name, 'Microsoft.Compute', "disks/#{disk_name}"), api_version: API_VERSIONS[:disks])
    end

    def check_vm_status(rg_name, vm_name)
      vm = @client.get(rg_provider_path(rg_name, 'Microsoft.Compute', "virtualMachines/#{vm_name}"), api_version: API_VERSIONS[:compute], params: { '$expand' => 'instanceView' })
      get_status(vm)
    end

    def get_status(virtual_machine)
      statuses = virtual_machine.properties&.instance_view&.statuses || []
      statuses.each do |status|
        return status.code.split('/')[1] if status.code.include?('PowerState')
      end
      nil
    end

    def start_vm(rg_name, vm_name)
      compute_post(rg_name, "virtualMachines/#{vm_name}/start")
    end

    def stop_vm(rg_name, vm_name)
      compute_post(rg_name, "virtualMachines/#{vm_name}/powerOff")
      compute_post(rg_name, "virtualMachines/#{vm_name}/deallocate")
    end

    def self.gallery_caching(rg_name)
      @gallery_caching ||= {}
      @gallery_caching[rg_name] ||= {}
    end

    def actual_gallery_image_id(rg_name, image_id)
      gallery_names = list_galleries.map(&:name)
      return unless (gallery = gallery_names.first)
      gallery_image = list_gallery_images(rg_name, gallery).detect { |image| image.name == image_id }
      gallery_image&.id
    end

    def fetch_gallery_image_id(rg_name, image_id)
      AzureSdkAdapter.gallery_caching(rg_name)[image_id] ||= actual_gallery_image_id(rg_name, image_id)
    end

    private

    def sub_path(resource)
      "/subscriptions/#{@sub_id}/#{resource}"
    end

    def provider_path(provider, resource)
      "/subscriptions/#{@sub_id}/providers/#{provider}/#{resource}"
    end

    def rg_provider_path(rg_name, provider, resource)
      "/subscriptions/#{@sub_id}/resourceGroups/#{rg_name}/providers/#{provider}/#{resource}"
    end

    def compute_get(rg_name, resource)
      @client.get(rg_provider_path(rg_name, 'Microsoft.Compute', resource), api_version: API_VERSIONS[:compute])
    end

    def compute_put(rg_name, resource, body)
      @client.put(rg_provider_path(rg_name, 'Microsoft.Compute', resource), body, api_version: API_VERSIONS[:compute])
    end

    def compute_post(rg_name, resource)
      @client.post(rg_provider_path(rg_name, 'Microsoft.Compute', resource), nil, api_version: API_VERSIONS[:compute])
    end

    def compute_delete(rg_name, resource)
      @client.delete(rg_provider_path(rg_name, 'Microsoft.Compute', resource), api_version: API_VERSIONS[:compute])
    end

    def network_get(rg_name, resource)
      @client.get(rg_provider_path(rg_name, 'Microsoft.Network', resource), api_version: API_VERSIONS[:network])
    end

    def network_put(rg_name, resource, body)
      @client.put(rg_provider_path(rg_name, 'Microsoft.Network', resource), body, api_version: API_VERSIONS[:network])
    end

    def network_delete(rg_name, resource)
      @client.delete(rg_provider_path(rg_name, 'Microsoft.Network', resource), api_version: API_VERSIONS[:network])
    end
  end
end
