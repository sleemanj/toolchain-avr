#!/bin/bash
# This script uses the "crossbuild" Docker container to cross-compile the
# toolchain for various platforms.
USAGE="$(cat <<EOF
Usage: 
    $0 install-docker
      - Install Docker for you if your system meets certain requirements
      
    $1 install-crossbuild
      - Install the crossbuild Docker Container
    
    $0 compile {target}
      - Cross compile the toolchain for the given target, the resulting files 
        are left in objdir for you.
          
    $0 package {target} [outfile]
      - If the compile is not done, it will do so, then it will package the 
        compiled files into a suitable archive file.  
      
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
)"


DOCKER_CONTAINER_NAME=
# DOCKER_CONTAINER_NAME=multiarch/crossbuild:dev

function check_docker()
{
  # First you must have a working docker setup with the multiarch/crossbuild container
  if ! which docker
  then
    echo "$0: Docker is not installed, try \"$0 install-docker\" for an auto install" >&2
    echo "$0: Or follow the manual install instructions for Docker at" >&2
    echo "$0:   https://docs.docker.com/engine/installation/" >&2
    exit 1  
  fi
}

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
/usr/bin/${NATIVE_BIN} "$@"
EOF
      chmod +x /usr/bin/$native    
    fi
  done
}

case $1 in
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
    sudo apt-get install apt-transport-https ca-certificates linux-image-extra-$(uname -r) linux-image-extra-virtual
    sudo apt-key adv \
              --keyserver hkp://ha.pool.sks-keyservers.net:80 \
              --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get update
    
    sudo apt-get install docker-engine
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
  
  compile)
    # This needs to be called from outside the container
    if ! [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: compile needs to be called from outside the Docker container." >&2
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
    if ./tools.build
    then
      # For the canadian cross compile       
      #   [Us (Build)] x [Host] x [avr]       
      # we need first to build
      #   [ Us ] x [avr]
      # don't ask why, we just do OK
      if ! [ -d objdir-$(uname -i) ]
      then
        echo "First we need to build avr-gcc for $(uname -i) as the cross compile needs it, doing that now."
        
        if sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE=$(uname -i) $DOCKER_CONTAINER_NAME $0 _compile $(uname -i)
        then
          mv objdir objdir-$(uname -i)
          echo "The $(uname -i) compile is done, so now building avr-gcc for $2"
        else
          echo "The $(uname -i) compile failed, sorry." >&2
          exit 1
        fi        
      fi

      # Check to see if the cross-compile we requested was not really a cross-compile, and if so
      # just use the straight compiled one (well, it's still a cross from build to avr, but anyway you know what I mean)
      if [ "$(sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE=$2 $DOCKER_CONTAINER_NAME $0 _canonical_cross_triple)" =  "$(sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE==$(uname -i) $DOCKER_CONTAINER_NAME $0 _canonical_cross_triple)" ]
      then
        echo "... actually, we don't need to do that, just copying the one we already compiled for $(uname -i) as it is the same."
        cp -rp objdir-$(uname -i) objdir
        exit $?
      fi
               
      # Now we can call ourself in the docker and get the build happening
      sudo docker run -it --rm -v /home:/home -w $(pwd) -e CROSS_TRIPLE=$2 $DOCKER_CONTAINER_NAME $0 _compile $2
      exit $?  
      
    else
      echo "$0: Tools build failed, correct the problem, or ensure that tools.build exits with 0 status." >&2
      exit 1
    fi    
  ;;
   
  _canonical_cross_triple)
    # This needs to be called from inside the container
    if [ -z "$CROSS_TRIPLE" ]
    then
      echo "$0: _compile needs to be called from inside the Docker container." >&2
      exit 1
    fi
    echo $CROSS_TRIPLE
    exit 0
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

    PATH="$(pwd)/objdir-$(uname -i)/bin:$PATH"
    LD_LIBRARY_PATH="$(pwd)/objdir-$(uname -i)/lib:$LD_LIBRARY_PATH"
    
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
    export CONFARGS="--build=$(uname -i)-pc-linux-gnu --host=$1 $CONFARGS"
    
    # Everything cleaned up, except toolsdir which we keep
    rm -rf gcc gmp-${GMP_VERSION} mpc-${MPC_VERSION} mpfr-${MPFR_VERSION} binutils avr-libc libc avr8-headers gdb objdir *-build
    
    if ./tools.bash && \
       ./binutils.build.bash && \
       ./gcc.build.bash && \
       ./avr-libc.build.bash && \
       ./gdb.build.bash
    then
      echo "$1" >objdir/.build_target
      echo "Your build is complete, the files are in objdir"
      exit 0
    fi
    
    exit 1
  ;;

  *)    
    echo "$USAGE" >&2
    exit 1  
esac