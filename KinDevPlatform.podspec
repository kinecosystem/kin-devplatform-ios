Pod::Spec.new do |s|
  s.name             = 'KinDevPlatform'
  s.version          = '0.8.2'
  s.summary          = 'Kin Developer Platform SDK for iOS'
  s.description      = <<-DESC
Kin Developer Platform SDK for iOS
                       DESC

  s.homepage         = 'https://kinecosystem.org'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Kin' => 'kin@kinfoundation.com' }
  s.source           = { :git => 'https://github.com/kinecosystem/kin-devplatform-ios', :tag => s.version.to_s }

  s.ios.deployment_target = '8.1'

  s.source_files = 'KinEcosystem/**/*.{h,m,swift}'
  s.resources = 'KinEcosystem/**/*.{xcassets,xcdatamodeld,storyboard,xib,png,pdf,jpg,json}'
  s.swift_version = '4.1'
  s.dependency 'SimpleCoreDataStack', '0.1.6'
  s.dependency 'KinCoreSDK', '0.7.6'
end
