import re

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 添加 PBXFileReference
file_ref = '\t\tIMPORT778899 /* ImportFileView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ImportFileView.swift; sourceTree = "<group>"; };\n'
content = content.replace('/* End PBXFileReference section */', file_ref + '/* End PBXFileReference section */')

# 添加到 Views 组
content = content.replace(
    '\t\t\t\tFILTERCHIP778899 /* FilterChip.swift */,\n\t\t\t);\n\t\t\tpath = Views;',
    '\t\t\t\tFILTERCHIP778899 /* FilterChip.swift */,\n\t\t\t\tIMPORT778899 /* ImportFileView.swift */,\n\t\t\t);\n\t\t\tpath = Views;'
)

# 添加到 Sources Build Phase
content = content.replace(
    '\t\t\tOCCLCORR778899B /* OcclusionCorrector.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;',
    '\t\t\tOCCLCORR778899B /* OcclusionCorrector.swift in Sources */,\n\t\t\tIMPORT001122 /* ImportFileView.swift in Sources */,\n\t\t);\n\t\trunOnlyForDeploymentPostprocessing = 0;'
)

# 添加 BuildFile 引用
build_file_ref = '\t\tIMPORT001122 /* ImportFileView.swift in Sources */ = {isa = PBXBuildFile; fileRef = IMPORT778899 /* ImportFileView.swift */; };\n'
content = content.replace('/* End PBXBuildFile section */', build_file_ref + '/* End PBXBuildFile section */')

with open('FruitTreeScanner.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Done!")
