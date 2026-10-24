# 在 Runner.xcodeproj 加入 ShareExtension target（可重複執行）。
# 由 ../../setup_ios_share.command 呼叫；需要 CocoaPods 附帶的 xcodeproj gem。
require 'xcodeproj'

GROUP_ENT = 'Runner/Runner.entitlements'
EXT = 'ShareExtension'
BUNDLE = 'tw.toast.imageCompressor'

proj = Xcodeproj::Project.open(File.join(__dir__, 'Runner.xcodeproj'))
app = proj.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'

# Runner：App Group entitlements
app.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = GROUP_ENT }
runner_group = proj.main_group['Runner']
runner_group.new_reference('Runner.entitlements') unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }

if proj.targets.any? { |t| t.name == EXT }
  puts "#{EXT} target already exists"
else
  ext = proj.new_target(:app_extension, EXT, :ios, '15.0')
  group = proj.main_group.new_group(EXT, EXT)
  src = group.new_reference('ShareViewController.swift')
  group.new_reference('Info.plist')
  group.new_reference("#{EXT}.entitlements")
  ext.add_file_references([src])

  team = app.build_configurations.map { |c| c.build_settings['DEVELOPMENT_TEAM'] }.compact.first
  # 專案的設定（Debug / Release / Profile）都要有
  proj.build_configurations.map(&:name).each do |name|
    next if ext.build_configurations.any? { |c| c.name == name }
    base = ext.build_configurations.find { |c| c.name == 'Release' }
    c = ext.add_build_configuration(name, :release)
    c.build_settings.merge!(base.build_settings.dup)
  end
  ext.build_configurations.each do |c|
    s = c.build_settings
    s['INFOPLIST_FILE'] = "#{EXT}/Info.plist"
    s['GENERATE_INFOPLIST_FILE'] = 'NO'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE}.#{EXT}"
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT}/#{EXT}.entitlements"
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['DEVELOPMENT_TEAM'] = team if team
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    s['SKIP_INSTALL'] = 'YES'
    s['MARKETING_VERSION'] = '1.0.0'
    s['CURRENT_PROJECT_VERSION'] = '1'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end

  # 嵌入 App；放在 Flutter 的 Thin Binary 之前，避免 Xcode 的 build cycle
  embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13' # PlugIns
  bf = embed.add_file_reference(ext.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  thin = app.build_phases.find { |ph| ph.respond_to?(:name) && ph.name == 'Thin Binary' }
  if thin
    app.build_phases.delete(embed)
    app.build_phases.insert(app.build_phases.index(thin), embed)
  end
  app.add_dependency(ext)
  puts "#{EXT} target added"
end
proj.save
