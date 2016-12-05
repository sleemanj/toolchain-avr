<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [AVR Toolchain for Arduino](#avr-toolchain-for-arduino)
  - [Configuring](#configuring)
  - [Building - For Your Native System](#building---for-your-native-system)
    - [Debian requirements](#debian-requirements)
    - [Mac OSX requirements](#mac-osx-requirements)
    - [Windows requirements](#windows-requirements)
  - [Cross Compiling](#cross-compiling)
    - [Requirements](#requirements)
    - [Usage](#usage)
  - [Upstream credits](#upstream-credits)
  - [Credits](#credits)
  - [License](#license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## AVR Toolchain for Arduino

This is the AVR Toolchain used in the [Arduino IDE](http://arduino.cc/).

As soon as Atmel [ships a newer toolchain](http://distribute.atmel.no/tools/opensource/Atmel-AVR-GNU-Toolchain/), we pull the source code, **patch it** with some user contributed patches and deliver it with the [Arduino IDE](http://arduino.cc/).
Therefore, the resulting binaries may differ significantly from Atmel's. And you should start blaming us if things are not working as expected :)

### Configuring

Edit the `build.conf` file, currently the only thing worth changing is `AVR_VERSION` on the first line to match whatever the [latest version is](http://distribute.atmel.no/tools/opensource/Atmel-AVR-GNU-Toolchain/).

At time of writing, the latest toolchain available is based on Atmel 3.5.4 version. It contains:
 - binutils-2.26
 - gcc-4.9.2
 - avr-libc-2.0.0
 - gdb-7.8
 
### Building - For Your Native System

Setup has been done on partially set up development machines. If, trying to compile on your machine, you find any package missing from the following list, please open an issue at once! We all can't afford wasting time on setup :)

To just build, after getting the requirements...
```bash
./tools.bash
./binutils.build.bash
./gcc.build.bash
./libc.build.bash
./gdb.build.bash
```
after a successful compile the binaries etc will be found in `objdir`

To package, after getting the requirements...
```bash
./package-avr-gcc.bash
```

#### Debian requirements

```bash
sudo apt-get install build-essential gperf bison subversion texinfo zip automake flex libtinfo-dev pkg-config
```

#### Mac OSX requirements

You need to install MacPorts: https://www.macports.org/install.php. Once done, open a terminal and type:

```bash
sudo port selfupdate
sudo port upgrade outdated
sudo port install wget +universal
sudo port install automake +universal
sudo port install autoconf +universal
sudo port install gpatch +universal
```

#### Windows requirements

You need to install Cygwin: http://www.cygwin.com/. Once you have run `setup-x86.exe`, use the `Search` text field to filter and select for installation the following packages:

- git
- wget
- unzip
- zip
- gperf
- bison
- flex
- make
- patch
- automake
- autoconf
- gcc-g++
- texinfo (must be at version 4.13 since 5+ won't work)
- libncurses-devel

A note on texinfo: due to dependencies, each time you update/modify your cygwin installation (for example: you install an additional package), texinfo will be upgraded to version 5+, while you need version 4+!
Easy solution: as soon as you've installed the additional package, re-run cygwin setup, search texinfo, triple click on "Keep" until you read version 4, then click next.

You also need to install MinGW: http://www.mingw.org/. Once you have run mingw-get-setup.exe, select and install (clicking on "Installation" -> "Apply changes") the following packages:

- mingw-developer-toolkit
- mingw32-base
- mingw32-gcc-g++
- msys-base
- msys-zip

### Cross Compiling

The Arduino IDE is available on a number of platforms so everything needs to be compiled for those other systems too.  To make this job a bit easier a cross compiling script is available.

#### Requirements

The crossbuild requires an Ubuntu 64bit Linux, (trusty, wily or xenial should be OK) with Kernel greater than 3.10 (those ubuntus should already qualify).

Docker is required, however the script can install it for you.

multiarch/crossbuild Docker container is required, however the script can install it for you.

Docker runs as root, or requires root to run it, so you need sudo access.

It is highly recommended that instead of doing this on your own machine, you spin up a beefy Amazon EC2 or similar VPS type of instance with a suitable Ubuntu on it.   The compilation process is long and CPU intensive, if you use an Amazon EC2 micro instance you will be there for days.

#### Usage

First if you don't have it you want to setup Docker

    ./crossbuild.bash install-docker
    
Then the crossbuild environment

    ./crossbuild.bash install-crossbuild
    
Then you can compile for a given target

    ./crossbuild.bash compile {target}
    
The list of targets (not all tested!) can be obtained by 

    ./crossbuild
    
but generally should be one of 

  * linux64, linux32
  * windows64, windows32
  * mac64, mac64h, mac32
  
( note that mac64h is for Haswell - I don't know enough about architecture to know if mac64 works on 64h macs or not, maybe you don't need it )

After some time, the compilation will complete (or fail, but let's assume it worked), the compiled toolchain for your target is in the objdir.  To package this toolchain into the relative archive, simply...

    ./crossbuild package
    
after some zipping action, the package archive will be put into the `packages/` directory, with a suitable filename.

If somethng goes wrong with the compile, you might want to get a shell into the crossbuild container with

    ./crossbuild shell {target}
    
then you can try and resolve the issue.  Remember that this is a Docker Container, any changes you make to the system will not persist once you exit the container - except in the toolchain directory which is (sort of) loopback mounted into the container.  Note that the patches directories are also not persistent, see the `submodule_patches_dir()` function in `crossbuild.bash` for why that is.

### Upstream credits

Build process ported from Debian. Most patches come from Atmel. Thank you guys for your awesome work.

### Credits

Consult the [list of contributors](https://github.com/arduino/toolchain-avr/graphs/contributors).

### License

The bash scripts are GPLv2 licensed. Every other software used by these bash scripts has its own license. Consult them to know the terms.

