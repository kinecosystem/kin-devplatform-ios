# Uncomment the next line to define a global platform for your project
platform :ios, '9.0'

use_frameworks!
inhibit_all_warnings!

workspace 'KinDevPlatform'

target 'KinDevPlatform' do
  project 'KinDevPlatform/KinDevPlatform.xcodeproj'

  pod 'SimpleCoreDataStack'
  pod 'KinMigrationModule', '0.1.1'
  pod 'KinSDK', '0.9.1'
  pod 'KinCoreSDK', '0.8.1'
end

target 'KinDevPlatformSampleApp' do
  project 'KinDevPlatformSampleApp/KinDevPlatformSampleApp.xcodeproj'

  pod 'KinDevPlatform', :path => './'
  pod 'JWT', '3.0.0-beta.11'
end