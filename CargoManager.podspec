Pod::Spec.new do |s|
  s.name = 'CargoManager'
  s.version = '0.5.0'
  s.license = 'FreeBSD'
  s.summary = 'CargoManager is an open source library that helps you implement IAPs for iOS apps in a simple and encapsulated way by using the by using the delegate pattern.'
  s.homepage = 'https://github.com/victorwon/CargoManager'
  s.author = 'Yang & Ricardo'
  s.source = { :git => 'https://github.com/victorwon/CargoManager.git', :tag => "v#{s.version}" }
  s.source_files = 'CargoManager/CargoManager.{h,m}'
  s.platform = :ios, '7.0'
  s.frameworks = 'StoreKit'
  s.requires_arc = true
  s.dependency 'CargoBay', '~> 2.1'

end
