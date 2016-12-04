#!/bin/bash
# This script uses the "crossbuild" Docker container to cross-compile the
# toolchain for various platforms.

DOCKER_CONTAINER_NAME=
# DOCKER_CONTAINER_NAME=multiarch/crossbuild:dev

function check_docker()
{
  # First you must have a working docker setup with the multiarch/crossbuild container
  if ! which docker
  then
    echo "$0: Docker is not installed, follow the installation instructions for Docker at" >&2
    echo "$0: https://docs.docker.com/engine/installation/" >&2
    exit 1  
  endif

  if [ -z "$DOCKER_CONTAINER_NAME" ]
  then
    DOCKER_CONTAINER_NAME="$(sudo docker images multiarch/crossbuild --format "{{.Repository}}:{{.Tag}}")"
    if [ -z "$DOCKER_CONTAINER_NAME" ]
    then
      echo "$0: Docker multiarch/crossbuild container is not installed (or not found)." >&2
      echo "$0: To install... " >&2
      echo "$0:   cd /tmp && git clone https://github.com/multiarch/crossbuild.git && cd crossbuild && sudo make" >&2
      echo "$0: (if you setup non-root access to docker you won't need the sudo)" >&2
      exit 1
    fi
  fi
}

# The crossbuild container needs some tweaks for us.
function tweak_docker_container()
{
  # Some extra tools we need that might not be in the container already
  apt-get update && apt-get install flex bison texinfo

  # We need to be able to compile stuff for the container, in the container
  # https://github.com/multiarch/crossbuild/issues/26

  for native in gcc g++ ar as dlltool gck gfortran gccgo ld nm ranlib windmc windres
  do
    if [ -L /usr/bin/$native ]
    then
      NATIVE_BIN="$(realpath /usr/bin/$native)"
      rm /usr/bin/$native
      cat >/usr/bin/$native <<'EOF'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_LIBRARY_PATH=/usr/lib:/lib
/usr/bin/${NATIVE_BIN} $@
EOF
      chmod +x /usr/bin/$native    
    fi
  done
}



case $1 in
  compile)
    # This needs to be called from outside the container
    if ! [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: compile needs to be called from outside the Docker container." >&2
      exit 1
    fi

    if [ -z "$2" ]
    then
      echo >&2 <<'EOF'
Usage: $0 compile {target} [output]

    Targets can be specified as the below (all targets on the same line are just aliases).    

    Linux Targets:
        x86_64-linux-gnu, linux, x86_64, amd64      
        arm-linux-gnueabi, arm, armv5      
        arm-linux-gnueabihf, armhf, armv7, armv7l      
        aarch64-linux-gnu, arm64, aarch64     
        mipsel-linux-gnu, mips, mipsel      
        powerpc64le-linux-gnu, powerpc, powerpc64, powerpc64le     
 
    Macintosh Targets:
        x86_64-apple-darwin, osx, osx64, darwin, darwin64      
        x86_64h-apple-darwin, osx64h, darwin64h, x86_64h      
        i386-apple-darwin, osx32, darwin32      
        *-apple-darwin      

    Windows Targets:
        x86_64-w64-mingw32, windows, win64      
        i686-w64-mingw32, win32
EOF
    
    fi



    # Check that docker is installed and the container is built
    check_docker

    # The tools we need, they get built outside the container
    if ./tools.build
    then
      # Now we can call ourself in the docker and get the build happening
      sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE=$2  $DOCKER_CONTAINER_NAME $0 _compile $2
      exit $?
    else
      echo "$0: Tools build failed, correct the problem, or ensure that tools.build exits with 0 status." >&2
      exit 1
    fi

    
  ;;

  _compile)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: _compile needs to be called from inside the Docker container." >&2
      exit 1
    fi

    # Make sure our container has the stuff we need
    tweak_docker_container

    # When compiling binutils and avr-gcc it needs to compile some stuff in the 
    # container for use in the container, we have to explicitly point it to the
    # right compiler to use (crossbuild has prepended the crosses in the path)
    CC_FOR_BUILD=/usr/bin/gcc
    CXX_FOR_BUILD=/usr/bin/g++
    AR_FOR_BUILD=/usr/bin/ar
    AS_FOR_BUILD=/usr/bin/as
    LD_FOR_BUILD=/usr/bin/ld
    NM_FOR_BUILD=/usr/bin/nm
    RANLIB_FOR_BUILD=/usr/bin/ranlib

    # We need to tell autoconf that we are cross compiling
    # indeed we are doing a Canadian Cross but the --target=avr is 
    # added in the build scripts.
    CROSS_CONF_FLAGS="--build=$(uname -i)-pc-linux-gnu --host=$1"
           
  ;;

  *)
    echo "Usage: $0 compile {target} [output]" >&2
    exit 1  
esac