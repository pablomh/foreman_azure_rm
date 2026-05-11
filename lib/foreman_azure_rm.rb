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
    VirtualMachine = OpenStruct
    VirtualMachineExtension = OpenStruct
    HardwareProfile = OpenStruct
    OSProfile = OpenStruct
    LinuxConfiguration = OpenStruct
    SshConfiguration = OpenStruct
    SshPublicKey = OpenStruct
    StorageProfile = OpenStruct
    OSDisk = OpenStruct
    ManagedDiskParameters = OpenStruct
    DataDisk = OpenStruct
    ImageReference = OpenStruct
    PurchasePlan = OpenStruct
    NetworkInterfaceReference = OpenStruct
    NetworkProfile = OpenStruct
  end

  module NetworkModels
    IPAllocationMethod = OpenStruct.new(
      Dynamic: 'Dynamic',
      Static: 'Static'
    )
    NetworkInterface = OpenStruct
    NetworkInterfaceIPConfiguration = OpenStruct
    PublicIPAddress = OpenStruct
  end
end
