#!/bin/sh
set -e

die()
{
    echo >&2 $@
    exit 1
}

if [ "$DC" = "" ]; then
	command -v gdmd >/dev/null 2>&1 && DC=gdmd || true
	command -v ldmd2 >/dev/null 2>&1 && DC=ldmd2 || true
	command -v dmd >/dev/null 2>&1 && DC=dmd || true
fi

# Quick hack to enable dub on Raspi
if [ "$(uname -m)" = "armv6l" ] ; then
    echo "Building dub for Raspberry Pi..."
    echo ""
    echo "WARNING: This feature is experimental and might break."
    echo "         You may have to taint the code or this build script to achieve your needs."
    echo "         You have been warned."
    echo ""
    echo "GDC is used to build dub. You can find builds: http://gdcproject.org/downloads/"
    echo "Make sure it is included in your path, or export the variable \"DC\" prior to this script."
    echo "eg: DC=/home/pi/gdc-4.9/bin/gdc ./build.sh"
    echo ""

    command -v gdc >/dev/null 2>&1 && DC=gdc || die "Error: gdc not found in your PATH"
    LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`
    # See below
    LIBS="-l:libgphobos2.a $LIBS"

    echo Generating version file...
    GITVER=$(git describe) || GITVER=unknown
    echo "module dub.version_; enum dubVersion = \"$GITVER\";" > source/dub/version_.d

    echo Running $DC...
    for source in $(cat build-files.txt); do
	mkdir -p objs/$(dirname $source)
	output="objs/${source%.d}.o"
	if [ ! -r $output ]; then
	    echo "Building $source... "
	    $DC -o $output -g --debug -w --version=DubUseCurl -c -Isource $* $source
	else
	    echo "$output already present, skipping it..."
	fi
    done
    echo "Linking..."
    $DC -o bin/dub -g --debug -w --version=DubUseCurl -Isource $* $LIBS $(find objs -name "*.o")
    echo DUB has been built as bin/dub.
    exit 0
fi

if [ "$DC" = "" ]; then
	echo >&2 "Failed to detect D compiler. Use DC=... to set a dmd compatible binary manually."
	exit 1
fi

# link against libcurl
LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`

# fix for modern GCC versions with --as-needed by default
if [ "$DC" = "dmd" ]; then
	if [ `uname` = "Linux" ]; then
		LIBS="-l:libphobos2.a $LIBS"
	else
		LIBS="-lphobos2 $LIBS"
	fi
elif [ "$DC" = "ldmd2" ]; then
	LIBS="-lphobos-ldc $LIBS"
fi

# adjust linker flags for dmd command line
LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`

echo Generating version file...
GITVER=$(git describe) || GITVER=unknown
echo "module dub.version_;" > source/dub/version_.d
echo "enum dubVersion = \"$GITVER\";" >> source/dub/version_.d
echo "enum initialCompilerBinary = \"$DC\";" >> source/dub/version_.d


echo Running $DC...
$DC -ofbin/dub -g -debug -w -version=DubUseCurl -Isource $* $LIBS @build-files.txt
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
