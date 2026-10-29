Pod::Spec.new do |s|
  s.name             = 'flutter_bluetooth_classic'
  s.version          = '1.0.4'
  s.summary          = 'Flutter plugin for Bluetooth communication.'
  s.description      = <<-DESC
Flutter plugin for Bluetooth device discovery, connection management and data transmission.
                       DESC
  s.homepage         = 'https://github.com/C0DE-IN/flutter_bluetooth_classic'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'C0DE-IN' => 'vigneshwaran.india@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'ExternalAccessory'
  s.platform         = :ios, '12.0'

  # DEFINES_MODULE lets GeneratedPluginRegistrant.m `@import` the Swift-only plugin.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
