require 'foreman_azure_rm/engine.rb'

module ForemanAzureRm
  module ComputeModels
    CachingTypes = OpenStruct.new(
      None: 'None',
      ReadOnly: 'ReadOnly',
      ReadWrite: 'ReadWrite'
    )
    DiskCreateOption = OpenStruct.new(Empty: 'Empty')
    DiskCreateOptionTypes = OpenStruct.new(FromImage: 'FromImage')
    StorageAccountTypes = OpenStruct.new(
      PremiumLRS: 'Premium_LRS',
      StandardLRS: 'Standard_LRS'
    )
  end

  module NetworkModels
    IPAllocationMethod = OpenStruct.new(
      Dynamic: 'Dynamic',
      Static: 'Static'
    )
  end
end
