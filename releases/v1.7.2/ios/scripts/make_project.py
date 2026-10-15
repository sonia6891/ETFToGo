"""Regenerate a dependency-free Xcode project. Existing product code/assets are preserved."""
from pathlib import Path
import hashlib,json,plistlib
ROOT=Path(__file__).resolve().parents[1]
def uid(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s):return json.dumps(str(s),ensure_ascii=False)
objects={}
def add(key,body): objects[uid(key)]=body;return uid(key)
files=sorted((ROOT/'ETFToGo').rglob('*.swift'))
refs=[];sources=[]
for path in files:
 rel=path.relative_to(ROOT).as_posix()
 ref=add('ref:'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = "<group>";')
 refs.append(ref);sources.append(add('build:'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
resources=[]
for rel,kind in [('ETFToGo/Assets.xcassets','folder.assetcatalog'),('ETFToGo/Resources/catalog.json','text.json'),('ETFToGo/Resources/PrivacyInfo.xcprivacy','text.xml')]:
 ref=add('ref:'+rel,f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(rel)}; sourceTree = "<group>";');refs.append(ref)
 resources.append(add('build:'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ETFToGo.app; sourceTree = BUILT_PRODUCTS_DIR;')
def arr(items):return '('+','.join(items)+(',' if items else '')+')'
products=add('products',f'isa = PBXGroup; children = {arr([product])}; name = Products; sourceTree = "<group>";')
group=add('mainGroup',f'isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>";')
sourcesPhase=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;')
resourcesPhase=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks=add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
configs={}
for kind in ['project','target']:
 ids=[]
 for mode in ['Debug','Release']:
  settings={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0'}
  if kind=='target':settings.update({'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.sonia.etftogo','INFOPLIST_FILE':'ETFToGo/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'})
  if mode=='Debug':settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG','ENABLE_TESTABILITY':'YES','DEBUG_INFORMATION_FORMAT':'dwarf'})
  else:settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-O','SWIFT_COMPILATION_MODE':'wholemodule','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
  body=' '.join(f'{k} = {q(v)};' for k,v in settings.items())
  ids.append(add(kind+mode,f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {mode};'))
 configs[kind]=add(kind+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {configs["target"]}; buildPhases = {arr([sourcesPhase,frameworks,resourcesPhase])}; buildRules = (); dependencies = (); name = ETFToGo; productName = ETFToGo; productReference = {product}; productType = "com.apple.product-type.application";')
project=add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {configs["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hant"; hasScannedForEncodings = 0; knownRegions = ("zh-Hant", en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
path=ROOT/'ETFToGo.xcodeproj';path.mkdir(exist_ok=True)
(path/'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1; classes = {}; objectVersion = 56;\nobjects = {\n'+ '\n'.join(f'{key} = {{ {value} }};' for key,value in objects.items())+'\n};\nrootObject = '+project+';\n}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ETFToGo.app" BlueprintName="ETFToGo" ReferencedContainer="container:ETFToGo.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ETFToGo.app" BlueprintName="ETFToGo" ReferencedContainer="container:ETFToGo.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ETFToGo.app" BlueprintName="ETFToGo" ReferencedContainer="container:ETFToGo.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
scheme_path=path/'xcshareddata/xcschemes/ETFToGo.xcscheme';scheme_path.parent.mkdir(parents=True,exist_ok=True);scheme_path.write_text(scheme)
print(f'Generated project with {len(files)} Swift files, {len(resources)} resource entries; target {target}')
