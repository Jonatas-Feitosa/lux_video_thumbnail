Pod::Spec.new do |s|
  s.name             = 'lux_video_thumbnail_ios'
  s.version          = '1.0.0-dev.1'
  s.summary          = 'AVFoundation video thumbnail extraction for Flutter.'
  s.description      = 'Reusable video sessions, JPEG/PNG thumbnails and bounded temporary resources on iOS.'
  s.homepage         = 'https://github.com/Jonatas-Feitosa/lux_video_thumbnail'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Jonatas Feitosa' => 'https://github.com/Jonatas-Feitosa' }
  s.source           = { :path => '.' }
  s.source_files     = 'lux_video_thumbnail_ios/Sources/lux_video_thumbnail_ios/**/*.swift'
  s.resource_bundles = { 'lux_video_thumbnail_ios_privacy' => ['lux_video_thumbnail_ios/Sources/lux_video_thumbnail_ios/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'AVFoundation', 'UIKit'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
