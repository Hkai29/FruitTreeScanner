import re

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 添加 PBXFileReference
file_ref = '\t\tSCANQUAL778899 /* ScanQualityMonitor.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScanQualityMonitor.swift; sourceTree = "<group>"; };\n'
content = content.replace('/* End PBXFileReference section */', file_ref + '/* End PBXFileReference section */')

# 添加到 Core 组
content = content.replace(
    '\t\t\t\tOCCLCORR778899 /* OcclusionCorrector.swift */,\n\t\t\t);\n\t\t\tpath = Core;',
    '\t\t\t\tOCCLCORR778899 /* OcclusionCorrector.swift */,\n\t\t\t\tSCANQUAL778899 /* ScanQualityMonitor.swift */,\n\t\t\t);\n\t\t\tpath = Core;'
)

# 添加到 Sources Build Phase
content = content.replace(
    '\t\t\tIMPORT001122 /* ImportFileView.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;',
    '\t\t\tIMPORT001122 /* ImportFileView.swift in Sources */,\n\t\t\tSCANQUAL001122 /* ScanQualityMonitor.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;'
)

# 添加 BuildFile 引用
build_file_ref = '\t\tSCANQUAL001122 /* ScanQualityMonitor.swift in Sources */ = {isa = PBXBuildFile; fileRef = SCANQUAL778899 /* ScanQualityMonitor.swift */; };\n'
content = content.replace('/* End PBXBuildFile section */', build_file_ref + '/* End PBXBuildFile section */')

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Done!")
