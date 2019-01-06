# Uncomment the next line to define a global platform for your project
platform :ios, '9.0'

use_frameworks!
inhibit_all_warnings!

workspace 'KinDevPlatform'

target 'KinDevPlatform' do
  project 'KinDevPlatform/KinDevPlatform.xcodeproj'

  pod 'SimpleCoreDataStack'
  pod 'KinMigrationModule', :path => '../kin-migration-module-ios'

  # Fixes the framework tests failing to build
#   target 'KinDevPlatformSampleApp' do
#     inherit! :search_paths
#   end
end

target 'KinDevPlatformSampleApp' do
  project 'KinDevPlatformSampleApp/KinDevPlatformSampleApp.xcodeproj'

  pod 'KinDevPlatform', :path => './'
end