# 64-bit build. For 32-bit builds, replace
# build-win64.txt with build-win32.txt
meson setup --cross-file build-win32.txt --buildtype release --prefix ([System.IO.Path]::GetFullPath("build")) build.w32
cd build.w32
ninja install
cd ..