Pod::Spec.new do |s|
  s.name        = 'KinDevPlatform'
  s.version     = '1.0.9'
  s.summary     = 'Kin Developer Platform SDK for iOS'
  s.description = 'Kin Developer Platform SDK for iOS'
  s.homepage    = 'https://github.com/kinecosystem/kin-devplatform-ios'
  s.license     = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author      = { 'Kin' => 'info@kin.org' }
  s.source      = { :git => 'https://github.com/kinecosystem/kin-devplatform-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.1'

  s.source_files = 'KinDevPlatform/KinDevPlatform/**/*.{h,m,swift}'
  s.resources = 'KinDevPlatform/KinDevPlatform/**/*.{xcassets,xcdatamodeld,storyboard,xib,png,pdf,jpg,json}'
  s.swift_version = '4.2'

  s.dependency 'SimpleCoreDataStack', '0.1.6'
  s.dependency 'KinMigrationModule', '0.0.4'
end
