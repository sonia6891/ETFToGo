#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_root/.build/direct-core"
mkdir -p "$build_dir"
compiler="${SWIFTC:-swiftc}"
flags=()
if [[ -n "${SWIFT_CLANG_INCLUDE:-}" ]]; then flags+=(-Xcc "-I$SWIFT_CLANG_INCLUDE"); fi
extension=so
if [[ "$(uname -s)" == Darwin ]]; then extension=dylib; fi
"$compiler" "${flags[@]}" -emit-library -emit-module -enable-testing -module-name ETFCore "$project_root"/ETFToGo/Core/*.swift -o "$build_dir/libETFCore.$extension" -emit-module-path "$build_dir/ETFCore.swiftmodule"
python3 - "$project_root" "$build_dir" <<'PY'
import pathlib,re,sys
root,out=map(pathlib.Path,sys.argv[1:])
names=re.findall(r'func (test\w+)\(', (root/'Tests/ETFCoreTests/CoreTests.swift').read_text())
(out/'main.swift').write_text('import XCTest\nXCTMain([testCase([\n'+',\n'.join('("'+n+'", CoreTests.'+n+')' for n in names)+'\n])])\n')
PY
"$compiler" "${flags[@]}" -I "$build_dir" -L "$build_dir" -lETFCore -Xlinker -rpath -Xlinker "$build_dir" "$project_root/Tests/ETFCoreTests/CoreTests.swift" "$build_dir/main.swift" -o "$build_dir/core-tests"
"$build_dir/core-tests"
