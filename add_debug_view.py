import re

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 添加 PBXFileReference
file_ref = '\t\tDEBUG778899 /* FruitDetectionDebugView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FruitDetectionDebugView.swift; sourceTree = "<group>"; };\n'
content = content.replace('/* End PBXFileReference section */', file_ref + '/* End PBXFileReference section */')

# 添加到 Views 组
content = content.replace(
    '\t\t\t\tIMPORT778899 /* ImportFileView.swift */,\n\t\t\t);\n\t\t\tpath = Views;',
    '\t\t\t\tIMPORT778899 /* ImportFileView.swift */,\n\t\t\t\tDEBUG778899 /* FruitDetectionDebugView.swift */,\n\t\t\t);\n\t\t\tpath = Views;'
)

# 添加到 Sources Build Phase
content = content.replace(
    '\t\t\tSCANQUAL001122 /* ScanQualityMonitor.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;',
    '\t\t\tSCANQUAL001122 /* ScanQualityMonitor.swift in Sources */,\n\t\t\tDEBUG001122 /* FruitDetectionDebugView.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;'
)

# 添加 BuildFile 引用
build_file_ref = '\t\tDEBUG001122 /* FruitDetectionDebugView.swift in Sources */ = {isa = PBXBuildFile; fileRef = DEBUG778899 /* FruitDetectionDebugView.swift */; };\n'
content = content.replace('/* End PBXBuildFile section */', build_file_ref + '/* End PBXBuildFile section */')

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Done!")
