# 64-bit build. For 32-bit builds, replace
# build-win64.txt with build-win32.txt
# &"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
&"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1" -Arch x86 -SkipAutomaticLocation
meson setup --reconfigure build-msvc-x86
meson setup --buildtype debug --backend vs2022 --prefix ([System.IO.Path]::GetFullPath("build")) build-msvc-x86
