#!/bin/bash
# This script uses the "crossbuild" Docker container to cross-compile the
# toolchain for various platforms.
USAGE="$(cat <<EOF
Usage: 
    $0 install-docker
      - Install Docker for you if your system meets certain requirements
      
    $0 install-crossbuild
      - Install the crossbuild Docker Container
    
    $0 compile {target}
      - Cross compile the toolchain for the given target, the resulting files 
        are left in objdir for you.
              
    $0 package {target}
      - If the compile is not done, it will do so, then it will package the 
        compiled files into a suitable archive file.  
      
    $0 shell {target}
      - Mainly for debugging, open a shell in the container configured for the 
        target compilation system.
      
    Targets can be specified as the below (all targets on the same line are just aliases).    

    Linux Targets:
        x86_64-linux-gnu, linux, x86_64, amd64      
        i386-linux-gnu, linux32, i386
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
)"

# The crossbuild container name, if blank we'll figure it out
#  typically multiarch/crossbuild:dev
DOCKER_CONTAINER_NAME=


# For some crosses we might need to disable patches so we use this function 
# to create a patches directory copy the patches we do want into it and 
# echo that directory, this will then be loopback mounted into the container 
# over the original patches
#
# $1 = Canonical Cross Triple
# $2 = Submodule
function submodule_patches_dir()
{
  # If there are no patches for this submodule, just use an empty directory
  if [ ! -d $2-patches ]
  then
    [ ! -d /tmp/no-patches ] && mkdir /tmp/no-patches
    echo -n /tmp/no-patches
    return 0
  fi
  
  # Copy the patches across into a temporary directory
  rm -rf /tmp/$2-patches
  cp -rp $2-patches /tmp/$2-patches
  
  # Remove patches we don't want
  case $2 in
    avr-gdb)
    
     if echo "$1" | grep "mingw" >/dev/null
     then
       rm -f /tmp/$2-patches/01-mingw-libtermcap*
     fi        
  esac
  
  echo -n /tmp/$2-patches
}

# Check that there is a working Docker installed
function check_docker()
{
  if ! which docker
  then
    echo "$0: Docker is not installed, try \"$0 install-docker\" for an auto install" >&2
    echo "$0: Or follow the manual install instructions for Docker at" >&2
    echo "$0:   https://docs.docker.com/engine/installation/" >&2
    exit 1  
  fi
}

# Check to see that the crossbuild dockert container is installed, and update
# DOCKER_CONTAINER_NAME
function check_crossbuild()
{  
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


# Run a command in the Docker container
# $1 = Canonical Cross Triple
# $2 = Command
# $3 = Argument
function run_in_docker()
{
    sudo docker run -it --rm -v /home:/home \
    -v $(submodule_patches_dir $1 binutils):$(pwd)/binutils-patches \
    -v $(submodule_patches_dir $1 avr-gcc):$(pwd)/avr-gcc-patches   \
    -v $(submodule_patches_dir $1 avr-libc):$(pwd)/avr-libc-patches \
    -v $(submodule_patches_dir $1 avr-gdb):$(pwd)/avr-gdb-patches   \
    -w $(pwd) -e CROSS_TRIPLE=$1 $DOCKER_CONTAINER_NAME $0 $2 $3
}

# The crossbuild container needs some tweaks for us.
# this is done from INSIDE the container.  Note that the changes are
# reset when the container exits, because that's how docker containers work.
function tweak_docker_container()
{
  # Some extra tools we need that might not be in the container already
  apt-get update && apt-get -y install flex bison texinfo

  # We need to be able to compile stuff for the container, in the container
  # https://github.com/multiarch/crossbuild/issues/26

  for native in gcc g++ ar as dlltool gck gfortran gccgo ld nm ranlib windmc windres
  do
    if [ -L /usr/bin/$native ]
    then
      NATIVE_BIN="$(realpath /usr/bin/$native)"
      rm /usr/bin/$native
      cat >/usr/bin/$native <<EOF
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_LIBRARY_PATH=/usr/lib:/lib
${NATIVE_BIN} "\$@"
EOF
      chmod +x /usr/bin/$native    
    fi
  done
}

# Take a target and return the canonical cross triple for it, resolving aliases
# we define some extra aliases ourself, and also allow the aliases from crossbuild
function canonical_cross_triple()
{
  case $1 in 
    linux64)
      echo x86_64-linux-gnu
    ;;
    
    windows64)
      echo x86_64-w64-mingw32
    ;;
    
    windows32)
      echo i686-w64-mingw32
    ;;
    
    mac64)
      echo x86_64-apple-darwin
    ;;
    
    mac64h)
      echo x86_64h-apple-darwin
    ;;
    
    mac32)
      echo i386-apple-darwin
    ;;
      
    i386-linux-gnu|linux32|i386)
      echo i386-linux-gnu
    ;;
  
    *)
      run_in_docker $1 _canonical_cross_triple
      # sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE=$1 $DOCKER_CONTAINER_NAME $0 _canonical_cross_triple
  esac
}


# The main program logic here, the actions prefixed with an underscore are executed
# INSIDE the container, and should only be called from the outside container actions
# not by the user directly.
case $1 in
  help)
    echo "$USAGE"
    exit 0
  ;;
  
  install-docker)
    # Only Ubuntu supported
    if ! [ "$(lsb_release -is)" = "Ubuntu" ]
    then  
      echo "$0: Sorry, I can't install Docker for you on a non-Ubuntu system." >&2
      echo "$0: See https://docs.docker.com/engine/installation/ for a manual install." >&2
      exit 1
    fi
    
    # Only certain versions of ubuntu supported
    case $(lsb_release -cs) in        
      # Add names of Ubuntu distributions we can handle here
      trusty|wily|xenial) echo -n ;;
      
      *)
        echo "$0: Sorry I don't know for sure how to install for Ubuntu $(lsb_release -cs).  Edit $0 around line $LINE to adjust this." >&2
        exit 1          
    esac
        
    # Double check the kernel version is new enough (it should be due the above, but anyway)
    if [  "3.10.0" = "$(echo -e "3.10.0\n$(uname -r)" | sort -V | tail -1)" ]
    then  
      echo "$0: Sorry we can not install Docker because your kernel is too old (requires Linux Kernel > 3.10.0, yours is $(uname -r))" >&2
      exit 1
    fi
    
    # Only 64 bit machines supported
    if ! [ "x86_64" = "$(uname -p)" ]
    then
      echo "$0: Sorry, Docker requires a 64bit OS, yours is $(uname -p) which doesn't seem to be that." >&2
      exit 1
    fi
        
    # Make absolutely sure they want to do this
    echo "Are you absolutely sure you want me to install Docker?"
    echo -n "Type yes<enter> to install, anything else to bail out: "
    if ! [ "$(read -e RESPONSE && echo $RESPONSE )" = "yes" ]
    then
      exit 1
    fi
                      
    # Ok, now we are following the install directions which are pretty simple
    # https://docs.docker.com/engine/installation/linux/ubuntulinux/
    sudo apt-get update 
    sudo apt-get -y install apt-transport-https ca-certificates linux-image-extra-$(uname -r) linux-image-extra-virtual
    sudo apt-key adv \
              --keyserver hkp://ha.pool.sks-keyservers.net:80 \
              --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get update
    
    sudo apt-get -y install docker-engine
    sudo service docker start
    
    echo 
    echo "Docker is now installed, in theory!"
    echo "Note that you can probably un-install it with apt-get [purge|remove] docker-engine"
    
    exit 0
  ;;

  install-crossbuild)
    check_docker
    pushd /tmp
    if [ -d crossbuild ]
    then
      echo "$0: crossbuild directory already exists, delete/move it to continue" >&2
      exit 1
    fi
      
    if git clone https://github.com/multiarch/crossbuild.git && cd crossbuild && sudo make && popd
    then
      echo "Crossbuild is now installed, in theory!"
      echo "Note that \"docker rmi multiarch/crossbuild:dev\" should remove it if you want."
      echo "Now you will want to do $0 compile [target]"
      exit 0
    else
      echo "$0: Crossbuild installation failed" >&2
      exit 1
    fi            
  ;;
  
  shell)
  # This needs to be called from outside the container
    if ! [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from outside the Docker container." >&2
      exit 1
    fi

    if [ -z "$2" ]
    then
      echo "$USAGE" >&2
      exit 1    
    fi

    # Check that docker is installed and the container is built
    check_docker
    check_crossbuild
    
    # The tools we need, they get built outside the container
    if ! [ -d toolsdir ]
    then
      if ! ./tools.bash 
      then
        echo "$0: Failed to compile the necessary tools." >&2
        [ -e toolsdir ] && echo "$0: Delete toolsdir before trying again." >&2
        exit 1
      fi    
    fi
    
    run_in_docker $(canonical_cross_triple $2) _shell    
  ;;
  
  compile)
    # This needs to be called from outside the container
    if ! [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from outside the Docker container." >&2
      exit 1
    fi

    if [ -z "$2" ]
    then
      echo "$USAGE" >&2
      exit 1    
    fi

    # Check that docker is installed and the container is built
    check_docker
    check_crossbuild
    
    # The tools we need, they get built outside the container
    if ! [ -d toolsdir ]
    then
      if ! ./tools.bash 
      then
        echo "$0: Failed to compile the necessary tools." >&2
        [ -e toolsdir ] && echo "$0: Delete toolsdir before trying again." >&2
        exit 1
      fi    
    fi
      
    # For the canadian cross compile       
    #   [Us (Build)] x [Host] x [avr]       
    # we need first to build
    #   [ Us ] x [avr]
    # this is both needed in order to build avr-gcc for [Host] and also
    # ultimately because we need to build avr-libc using avr-gcc ourselves
    if ! [ -d objdir-$(uname -m) ]
    then
      echo "First we need to build avr-gcc for $(uname -m) as the cross compile needs it, doing that now."
      
      if run_in_docker $(uname -m) _compile $(uname -m)
      then
        mv objdir objdir-$(uname -m)
        echo "The $(uname -m) compile is done, so now building for $2"
      else
        echo "The $(uname -m) compile failed, sorry." >&2
        exit 1
      fi        
    fi

    # Check to see if the cross-compile we requested was not really a cross-compile, and if so
    # just use the straight compiled one (well, it's still a cross from build to avr, but anyway you know what I mean)
    if [ "$(canonical_cross_triple $2)" =  "$(canonical_cross_triple "$(uname -m)")" ]
    then
      echo "... actually, we don't need to do that, just copying the one we already compiled for $(uname -m) as it is the same."
      rm -rf objdir
      cp -rp objdir-$(uname -m) objdir
      exit $?
    fi
     
    # We have to fudge the call for i386-linux-gnu because multiarch/crossbuild doesn't natively support it
    if [ "$(canonical_cross_triple $2)" = "i386-linux-gnu" ]
    then
      # The CROSS_TRIPLE here is a fake to satisfy the container's startup routine, _compile_linux32 will fix it
      run_in_docker x86_64-linux-gnu _compile_linux32 $2      
      exit $?      
    fi
    
    # For all other cross compiles we are now ready to go
    run_in_docker $(canonical_cross_triple $2) _compile $2
    exit $?      
  ;;
   
  _canonical_cross_triple)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from inside the Docker container." >&2
      exit 1
    fi
    
    echo -n $CROSS_TRIPLE
    exit 0
  ;;
    
  _shell)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from inside the Docker container." >&2
      exit 1
    fi

    # Make sure our container has the stuff we need
    tweak_docker_container
    
    PATH="$(pwd)/objdir-$(uname -m)/bin:$PATH"
    LD_LIBRARY_PATH="$(pwd)/objdir-$(uname -m)/lib:$LD_LIBRARY_PATH"
    
    # When compiling binutils and avr-gcc it needs to compile some stuff in the 
    # container for use in the container, we have to explicitly point it to the
    # right compiler to use (crossbuild has prepended the crosses in the path)
    export CC_FOR_BUILD=/usr/bin/gcc
    export CXX_FOR_BUILD=/usr/bin/g++
    export AR_FOR_BUILD=/usr/bin/ar
    export AS_FOR_BUILD=/usr/bin/as
    export LD_FOR_BUILD=/usr/bin/ld
    export NM_FOR_BUILD=/usr/bin/nm
    export RANLIB_FOR_BUILD=/usr/bin/ranlib

    # We need to tell autoconf that we are cross compiling
    # indeed we are doing a Canadian Cross but the --target=avr is 
    # added in the build scripts.
    export CONFARGS="--build=$(uname -m)-pc-linux-gnu --host=$CROSS_TRIPLE $CONFARGS"
        
    bash
  ;;
    
  _compile)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from inside the Docker container." >&2
      exit 1
    fi

    # Make sure our container has the stuff we need
    tweak_docker_container

    PATH="$(pwd)/objdir-$(uname -m)/bin:$PATH"
    LD_LIBRARY_PATH="$(pwd)/objdir-$(uname -m)/lib:$LD_LIBRARY_PATH"
    
    # When compiling binutils and avr-gcc it needs to compile some stuff in the 
    # container for use in the container, we have to explicitly point it to the
    # right compiler to use (crossbuild has prepended the crosses in the path)
    export CC_FOR_BUILD=/usr/bin/gcc
    export CXX_FOR_BUILD=/usr/bin/g++
    export AR_FOR_BUILD=/usr/bin/ar
    export AS_FOR_BUILD=/usr/bin/as
    export LD_FOR_BUILD=/usr/bin/ld
    export NM_FOR_BUILD=/usr/bin/nm
    export RANLIB_FOR_BUILD=/usr/bin/ranlib

    # We need to tell autoconf that we are cross compiling
    # indeed we are doing a Canadian Cross but the --target=avr is 
    # added in the build scripts.
    export CONFARGS="--build=$(uname -m)-pc-linux-gnu --host=$CROSS_TRIPLE $CONFARGS"
    
    # Everything cleaned up, except toolsdir which we keep
    rm -rf gcc gmp-${GMP_VERSION} mpc-${MPC_VERSION} mpfr-${MPFR_VERSION} binutils avr-libc libc avr8-headers gdb objdir
        
    # Compile the subunits in order, note that the tools are already done (outside of the container)
    for subunit in binutils gcc avr-libc gdb
    do
      # If it's not built, or if it was built for a different target, (re)build
      if [ ! -d "${subunit}-build" ] || [ "$(cat "${subunit}-build/.build_target")" != "$CROSS_TRIPLE" ] 
      then
        rm -rf {subunit}-build
        if ! ./${subunit}.build.bash
        then
          echo "$0: Failed to compile ${subunit}" >&2
          exit 1
        fi
        echo $CROSS_TRIPLE >${subunit}-build/.build_target
      else
        # Already compiled we will just do the install again        
        pushd ${subunit}-build
      
        if ! make install
        then
          echo "$0: Failed to install ${subunit} from precompiled ${subunit}-build" >&2
          exit 1
        fi
        
        popd
      fi      
    done    
           
    echo "$CROSS_TRIPLE" >objdir/.build_target
    echo "Your build is complete, the files are in objdir"
    exit 0
  ;;
  
  _compile_linux32)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: $1 needs to be called from inside the Docker container." >&2
      exit 1
    fi
    
    # Because of https://github.com/multiarch/crossbuild/issues/7
    # multiarch/crossbuild doesn't quite support 32bit linux compilation
    # but we can fix it on-the-fly by installing the multilib
    # (which will kill cross compile ability but since this is a container
    #  it doesn't matter as such things do not persist) and wrapping 
    # gcc and g++ to tell them to do a 32bit compile
    # Note that you will have to supply a "legal" CROSS_TRIPLE when starting
    # the container (x86_64-linux-gnu will do) or the container will error out.
    
    CROSS_TRIPLE=i386-linux-gnu
    sudo apt-get -y install gcc-multilib g++multi-lib
    
    for native in gcc g++
    do
      if [ -L /usr/bin/$native ]
      then
        NATIVE_BIN="$(realpath /usr/bin/$native)"
        rm /usr/bin/$native
        cat >/usr/bin/$native <<EOF
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_LIBRARY_PATH=/usr/lib:/lib
${NATIVE_BIN} -m32 "\$@"
EOF
        chmod +x /usr/bin/$native    
      fi
    done
  
    # Now we can carry on as normal
    $0 _compile
  ;;
  
  *)    
    echo "$USAGE" >&2
    exit 1  
esac