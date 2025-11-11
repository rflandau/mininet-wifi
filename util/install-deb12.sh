#!/usr/bin/env bash

# Mininet-Wifi install script for Debian 12
# Reuses some components from the base install script.
# Broken out for simplicity.
#
# Currently assumes the default -Wlnfv options.
# -W: wireless dependencies
# -l: wmediumd
# -n: mininet-wifi dependencies
# -f: OpenFlow
# -v: OpenvSwitch


#region strict mode

# Fail on error
set -e

# Fail on unset var usage
set -o nounset

#endregion strict mode

#region required parameters

#OF_VERSION=1.0

MININET_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd -P )"

# Set up build directory, which by default is the working directory
#  unless the working directory is a subdirectory of mininet,
#  in which case we use the directory containing mininet
BUILD_DIR="$(pwd -P)"
case $BUILD_DIR in
  $MININET_DIR/*) BUILD_DIR=$MININET_DIR;; # currect directory is a subdirectory
  *) BUILD_DIR=$BUILD_DIR;;
esac

#endregion required parameters

# (-W) installs dependencies required for Mininet-wifi.
function wifi_deps {
    echo "Installing dependencies from apt..."
    sudo apt-get -y install \
        gcc make socat psmisc xterm ssh iperf telnet \
        ethtool help2man net-tools \
        wireless-tools rfkill pkg-config libnl-route-3-dev \
        libnl-3-dev libnl-genl-3-dev libssl-dev libevent-dev \
        libdbus-1-dev iproute2 cgroup-tools make patch
    sudo apt-get -y install \
        python3-setuptools python3-pip python3-pexpect \
        python3-tk python3-psutil python3-matplotlib \


    echo "Installing dependencies from pip..."
    # install the remaining python packages via pip.
    # NOTE(rlandau): this is against the standard Debian workflow, but should be okay for a packaged image.
    python3 -m pip install --upgrade pip
    python3 -m pip install "numpy<2" FlightRadarAPI pillow bitstring skyfield requests --break-system-packages

    # NOTE(rlandau): the rest is pulled directly from the original wifi_deps function in the install.sh.
    # It remains mostly intact (save for a now-unnecessary Ubuntu 14 check)
    echo "applying patches..."
    pushd $MININET_DIR/mininet-wifi
    git submodule update --init --recursive
    pushd $MININET_DIR/mininet-wifi/hostap
    patch -p0 < $MININET_DIR/mininet-wifi/util/hostap-patches/config.patch
    pushd $MININET_DIR/mininet-wifi/hostap/hostapd
    cp defconfig .config
    sudo make && make install
    pushd $MININET_DIR/mininet-wifi/hostap/wpa_supplicant
    cp defconfig .config
    sudo make && make install
    pushd $MININET_DIR/mininet-wifi/
    if [ -d iw ]; then
      echo "Removing iw..."
      rm -r iw
    fi
    git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/jberg/iw.git
    pushd $MININET_DIR/mininet-wifi/iw
    sudo make && make install
    cd $BUILD_DIR
    if [ -d mac80211_hwsim_mgmt ]; then
      echo "Removing mac80211_hwsim_mgmt..."
      rm -r mac80211_hwsim_mgmt
    fi
    git clone --depth=1 https://github.com/ramonfontes/mac80211_hwsim_mgmt.git
    pushd $BUILD_DIR/mac80211_hwsim_mgmt
    sudo make install
}


# (-l) installs wmediumd from git to /usr/bin/wmediumd
function wmediumd {
    echo "Installing wmediumd sources into $BUILD_DIR/wmediumd"
    cd $BUILD_DIR
    if [ -d wmediumd ]; then
      echo "Removing wmediumd..."
      rm -r wmediumd
    fi
    sudo apt-get -y install git make libevent-dev libconfig-dev libnl-3-dev libnl-genl-3-dev
    git clone --depth=1 -b mininet-wifi https://github.com/ramonfontes/wmediumd.git
    pushd $BUILD_DIR/wmediumd
    sudo make install
    popd
}

# (-n)
function mn_deps {
    echo "Installing Mininet core"
    pushd "$MININET_DIR"/mininet-wifi
    if [ -d mininet ]; then
      echo "Removing mininet dir..."
      rm -r mininet
    fi

    sudo git clone --depth=1 https://github.com/mininet/mininet.git
    pushd "$MININET_DIR"/mininet-wifi/mininet
    #if [ "$DIST" = "Ubuntu" ] &&  [ `expr $RELEASE '>=' 24.04` = "1" ]; then
    #    git reset --hard 6eb8973
    #    patch -p0 < $MININET_DIR/mininet-wifi/util/mininet-patches/mininet.patch
    #fi
    sudo PYTHON=python3 make install
    popd
    echo "Installing Mininet-wifi core"
    pushd "$MININET_DIR"/mininet-wifi
    sudo PYTHON=python3 make install
    popd
}

# (-f)
# The following will cause a full OF install, covering:
# -user switch
# The instructions below are an abbreviated version from
# http://www.openflowswitch.org/wk/index.php/Debian_Install
function of {
    echo "Installing OpenFlow reference implementation..."
    cd $BUILD_DIR
    sudo apt-get -y install autoconf automake libtool make gcc patch autotools-dev pkg-config libc6-dev
    
    git clone --depth=1 https://github.com/ramonfontes/openflow -b debian
    cd $BUILD_DIR/openflow

    # Patch controller to handle more than 16 switches
    patch -p1 < $MININET_DIR/mininet-wifi/util/openflow-patches/controller.patch

    # Resume the install:
    ./boot.sh
    ./configure
    make
    sudo make install
    cd $BUILD_DIR
}

# (-v)
function ovs {
    echo "Installing OpenvSwitch..."

    sudo apt-get -y install openvswitch-switch openvswitch-common
    OVSC=""
    echo "Attempting to install openvswitch-testcontroller"
    if sudo apt-get -y install openvswitch-testcontroller; then
        OVSC="openvswitch-testcontroller"
    else
        echo "Failed - skipping openvswitch-testcontroller"
    fi
    
    if [ "$OVSC" ]; then
        # Switch can run on its own, but
        # Mininet should control the controller
        # This appears to only be an issue on Ubuntu/Debian
        if sudo service $OVSC stop; then
            echo "Stopped running controller"
        fi
        if [ -e /etc/init.d/$OVSC ]; then
            sudo update-rc.d $OVSC disable
        fi
    fi
}

### RUN BLOCK

if [ $# -ne 0 ]; then
    exit 1;
fi

# confirm that we are running bookworm
if [[ ! $(cat /etc/debian_version) =~ ^12\. ]]; then
    exit 1;
fi

wifi_deps
mn_deps
of
ovs