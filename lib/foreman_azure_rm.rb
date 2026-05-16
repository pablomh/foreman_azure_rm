require 'foreman_azure_rm/engine.rb'

module ForemanAzureRm
  module ComputeModels
    module CachingTypes
      None = 'None'
      ReadOnly = 'ReadOnly'
      ReadWrite = 'ReadWrite'
    end
    module DiskCreateOption
      Empty = 'Empty'
    end
    module DiskCreateOptionTypes
      FromImage = 'FromImage'
    end
    module StorageAccountTypes
      PremiumLRS = 'Premium_LRS'
      StandardLRS = 'Standard_LRS'
    end
  end

  module NetworkModels
    module IPAllocationMethod
      Dynamic = 'Dynamic'
      Static = 'Static'
    end
  end
end
