#!/usr/bin/env bash
# TEMPORARY - #14781 regression matrix. Runs every LTO / archive / linker scenario
# for every installed clang and gcc, and appends one CSV row per case:
#   variant,image,case,result,warning
# result: PASS / FAIL / SKIP; warning: 1 if binutils printed a plugin error.
set -u
variant=$1
out=${RESULTS:?}
image="${ImageOS:-unknown}-$(uname -m)"
w=$(mktemp -d)
cd "$w"

# lib returns std::string / a large struct -> sret param -> newer LLVM attrs in IR
cat > lib.cpp <<'EOF'
#include <string>
std::string greet(int n) { return std::string("v") + std::to_string(n); }
EOF
cat > main.cpp <<'EOF'
#include <cstdio>
#include <string>
std::string greet(int);
int main() { std::puts(greet(42).c_str()); }
EOF
cat > lib.c <<'EOF'
struct big { long a[8]; };
struct big make(long n) { struct big b = {{0}}; b.a[7] = n; return b; }
EOF
cat > main.c <<'EOF'
#include <stdio.h>
struct big { long a[8]; };
struct big make(long);
int main(void) { printf("v%ld\n", make(42).a[7]); return 0; }
EOF
cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(lto CXX)
set(CMAKE_CXX_STANDARD 20)
add_library(mylib STATIC lib.cpp)
add_executable(app main.cpp)
target_link_libraries(app mylib)
EOF

# run_case <name> <shell script>; the script must produce ./app printing v42
run_case() {
  local name=$1 script=$2 log result warn
  rm -rf app build *.o *.a
  log=$(bash -c "set -e; $script" 2>&1 && ./app 2>&1)
  if [[ $? -eq 0 && "$log" == *v42* ]]; then result=PASS; else result=FAIL; fi
  warn=0; [[ "$log" == *"bfd plugin"* || "$log" == *"plugin needed to handle lto object"* ]] && warn=1
  echo "$variant,$image,$name,$result,$warn" >> "$out"
  if [[ $result == FAIL || $warn == 1 ]]; then
    echo "::group::$variant $name -> $result warn=$warn"; echo "$log" | tail -15; echo "::endgroup::"
  fi
}
skip() { echo "$variant,$image,$1,SKIP,0" >> "$out"; }

for v in $(ls -d /usr/lib/llvm-*/bin/clang 2>/dev/null | sed -E 's#.*/llvm-([0-9]+)/.*#\1#' | sort -n); do
  cxx=clang++-$v cc=clang-$v bin=/usr/lib/llvm-$v/bin
  run_case "clang$v full  | GNU ar | ld.bfd"   "$cxx -flto -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -flto -O2 main.cpp libx.a -o app"
  run_case "clang$v thin  | GNU ar | ld.bfd"   "$cxx -flto=thin -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -flto=thin -O2 main.cpp libx.a -o app"
  run_case "clang$v full  | GNU ar | gold"     "$cxx -flto -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -flto -O2 -fuse-ld=gold main.cpp libx.a -o app"
  run_case "clang$v full  | GNU ar | lld"      "$cxx -flto -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -flto -O2 -fuse-ld=lld main.cpp libx.a -o app"
  run_case "clang$v full  | objs   | ld.bfd"   "$cxx -flto -O2 main.cpp lib.cpp -o app"
  run_case "clang$v C     | GNU ar | ld.bfd"   "$cc -flto -O2 -c lib.c; ar rcs libx.a lib.o; $cc -flto -O2 main.c libx.a -o app"
  run_case "clang$v noLTO | GNU ar | ld.bfd"   "$cxx -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -O2 main.cpp libx.a -o app"
  run_case "clang$v GNU nm sees LTO symbols"   "$cxx -flto -O2 -c lib.cpp; nm lib.o | grep -q greet; $cxx -flto -O2 main.cpp lib.o -o app"
  if [[ -x $bin/llvm-ar ]]; then
    run_case "clang$v full  | llvm-ar | ld.bfd" "$cxx -flto -O2 -c lib.cpp; $bin/llvm-ar rcs libx.a lib.o; $cxx -flto -O2 main.cpp libx.a -o app"
  else skip "clang$v full  | llvm-ar | ld.bfd"; fi
  run_case "clang$v CMake -flto (GNU ar)"      "CXX=$cxx cmake -S . -B build -DCMAKE_CXX_FLAGS=-flto >/dev/null; cmake --build build; cp build/app app"
  run_case "clang$v CMake IPO"                 "CXX=$cxx cmake -S . -B build -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON >/dev/null; cmake --build build; cp build/app app"
done

for v in $(ls /usr/bin/g++-[0-9]* 2>/dev/null | sed -E 's#.*g\+\+-##' | sort -n); do
  cxx=g++-$v
  run_case "gcc$v -flto | GNU ar"     "$cxx -flto -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -flto -O2 main.cpp libx.a -o app"
  run_case "gcc$v -flto | gcc-ar"     "$cxx -flto -O2 -c lib.cpp; gcc-ar-$v rcs libx.a lib.o; $cxx -flto -O2 main.cpp libx.a -o app"
  run_case "gcc$v noLTO | GNU ar"     "$cxx -O2 -c lib.cpp; ar rcs libx.a lib.o; $cxx -O2 main.cpp libx.a -o app"
  run_case "gcc$v GNU nm sees LTO symbols" "$cxx -flto -O2 -c lib.cpp; nm lib.o | grep -q greet; $cxx -flto -O2 main.cpp lib.o -o app"
done
rm -rf "$w"
