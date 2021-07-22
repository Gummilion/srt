#!/bin/zsh

CUR_DIR=${0:a:h}
root=`cd ${CUR_DIR}/../..;pwd`
parent=`cd ${CUR_DIR}/..;pwd`

declare -A args
args[-ssl-dir]=$root/OpenSSL-for-iPhone
args[-platforms]='OS,SIMULATOR'
args[-out]=$build_dir/libsrt.xcframework
args[-ios-target]=12.0
args[-tvos-target]=12.0
args[-build-dir]=$parent/build_ios


if [[ -n $1 ]]
then
  zparseopts  -D -K -E -A args ssl-dir: build-dir: platforms: ios-target: tvos-target: out: h=help help=help -help=help
fi    

#for key val in "${(@kv)args}"; do
#    echo "$key -> $val"
#done

if [[ -n $help ]] 
then
    cat << EOF
Build static library for iOS wrapped to .xcframework container
Usage: $0 [-ssl-dir <path>] [-build-dir <path>] [-platforms <OS,SIMULATOR,TV,TV_SIMULATOR>] [-out <xcframework file>] [-ios-target version] [-tvos-target version]
    -h | -help: Show this message
    -ssl-dir: localtion of OpenSSL for iPhone; default: ${args[-build-dir]}
    -build-dir: Intermediate build directory; default: $root/OpenSSL-for-iPhone
    -platforms: list of platforms to build; supported values: OS,SIMULATOR,TV,TV_SIMULATOR; default: OS,SIMULATOR
    -out: location of .xcframework file; default: $build_dir/libsrt.xcframework
    -ios-target: target iOS version; default: ${args[-ios-target]}
    -tvos-target: target tvOS version; default: ${args[-ios-target]}
EOF
    return 0
fi

ssl=$args[-ssl-dir]
platforms=${args[-platforms]}
ios_platforms=("${(@s/,/)platforms}")
echo "OpenSSL for iPhone directory: $ssl"
echo "Build directory: ${args[-build-dir]}"
echo "platforms: $ios_platforms"
echo "Output library: ${args[-out]}"
echo "Target iOS SDK version: ${args[-ios-target]}" 
echo "Target tvOS SDK version: ${args[-tvos-target]}" 

if [[ ! ( -e $ssl/lib/libcrypto.a ) ]]
then
  echo Can\'t find OpenSSL library at path $ssl
  echo Install OpenSSL from https://github.com/x2on/OpenSSL-for-iPhone and build it prior to building SRT
  return 1
fi
 
srt=$parent
target=$args[-ios-target]
tv_target=$args[-tvos-target]
tvos_sdk=`xcrun -sdk appletvos --show-sdk-version`
lib=libsrt.a
build_dir=$args[-build-dir]

declare -A ios_archs
ios_archs=( [OS]=arm64 [SIMULATOR]=x86_64 [TV]=arm64 [TV_SIMULATOR]=x86_64 )
declare -A ios_targets
ios_targets=( [OS]=iOS-arm64 [SIMULATOR]=iOS-simIntel64 [TV]=tvOS [TV_SIMULATOR]=tvOS_simIntel64)

declare -a xcodebuild_params

xcodebuild_params=( "-create-xcframework" )

rm -rf $build_dir
mkdir $build_dir
cd $build_dir

for ((idx = 1; idx <= $#ios_platforms; idx++)); do
  mkdir build
  cd build
  ios_platform=${ios_platforms[$idx]}
  ios_arch=${ios_archs[$ios_platform]}
  dest=${ios_targets[$ios_platform]}
 
  if [[ -z $ios_arch ]]
  then
    echo Unknown platform: $ios_platform
    return 1
  fi
 
  case $ios_platform in 
    TV)
      ssl_path="${ssl}/bin/AppleTVOS${tvos_sdk}-${ios_arch}.sdk"
      ;;
    TV_SIMULATOR)  
      ssl_path="${ssl}/bin/AppleTVSimulator${tvos_sdk}-${ios_arch}.sdk"
      ;;
    *)
      ssl_path=$ssl 
      ;;
  esac

 echo '********************************************************************************'
 echo SSL_PATH $ssl_path ARCH $ios_arch PLATFORM $ios_platform

 $parent/configure --cmake-prefix-path=$ssl_path --use-openssl-pc=OFF --cmake-toolchain-file=$srt/scripts/iOS.cmake --ios-arch=$ios_arch --ios-platform=$ios_platform
 if [[ $ios_platform == TV* ]]
 then
  echo '####### build tvOS #######' 
  TVOS_DEPLOYMENT_TARGET=$tv_target make
 else 
  echo '####### build iOS #######' 
  IPHONEOS_DEPLOYMENT_TARGET=$target make
 fi  

 mkdir -p $build_dir/$dest
 cp $lib $build_dir/$dest
 
 if [[ $idx == 1 ]]
 then 
   # optionally export srt headers
  make install DESTDIR=$build_dir
 fi
 
 srt_headers=$build_dir/usr/local/include
 xcodebuild_params+=( -library $build_dir/$dest/$lib -headers $srt_headers )
 
 echo '********************************************************************************'
 cd ..
 rm -rf build/*
done

 xcodebuild_params+=( -output $args[-out] )

rm -rf $args[-out]

command xcodebuild $xcodebuild_params

#xcodebuild -create-xcframework -library $build_dir/iOS-arm64/$lib -headers $srt_headers \
# -library $build_dir/iOS-simIntel64/$lib -headers $srt_headers \
# -library $build_dir/tvOS/$lib -headers $srt_headers \
# -library $build_dir/tvOS_simIntel64/$lib -headers $srt_headers -output $args[-out]
