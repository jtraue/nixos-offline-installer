main() {

set -e
scriptlocation="$(dirname $(readlink -f $0))"

writeColor() {
  echo -e $3 "\e[40;1;$1m$2\e[0m"
}

informNotOk() {
  writeColor 31 "$1" "$2"
}

informOk() {
  writeColor 32 "$1" "$2"
}

fail() {
    informNotOk "Something went wrong, starting interactive shell..."
    exec setsid bash
}

trap 'fail' 0 ERR TERM INT

echo
informOk "<<< NixOS fully automated install >>>"
echo

## Bail out early if /installer is incomplete
if [ ! -d /installer ]; then
    informNotOk "Directory /installer missing"
    exit 1
fi

installImg=/installer/nixos-image
if [ ! -f $installImg ]; then
    informotOk "$installImg missing"
    exit 1
fi

export HOME=/root
cd ${HOME}

### Source configuration
interface=$(ip route list match default | awk '{print $5}')
mac_address=$(ip link show $interface | grep ether | awk '{print $2}')

informOk "Parsing custom configuration..."
try_config () {
    file=/installer/$1
    informOk "Trying $file..." -n
    if [ -f $file ]; then
        informOk "loading"
        . $file
    else
        informOk "not present"
    fi
}
try_config config-$ipv4Address
try_config config-$mac_address
try_config config
informOk "...custom configuration done"

#TODO: bail out on missing conf

informOk "Installing NixOS on device $rootDevice"

informOk "Using MBR"

wipefs -a $rootDevice
cat >> /tmp/partitions<< EOF
part swap --size=512 --ondisk=$rootDevice
part / --fstype=ext4 --label=nixroot --grow --ondisk=$rootDevice
EOF

nixpart /tmp/partitions

informOk "Installing NixOS"
informOk "Unpacking image $installImg..." -n
(cd /mnt && tar xapf $installImg)
chown -R 0:0 /mnt
informOk "done"

## Make the resolver config available in the chroot
cp /etc/resolv.conf /mnt

mkdir -p /mnt/tmp

## Generate hardware-specific configuration
#nixos-generate-config --root /mnt

## NIX path to use in the chroot
#TODO: channel might be called differently than "nixos"
export NIX_PATH=/nix/var/nix/profiles/per-user/root/channels:nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/${nixosConfigPath}

informOk "generating system configuration..."
## Starting with 18.09, nix.useSandbox defaults to true, which breaks the execution of
## nix-env in a chroot when the builder needs to be invoked because Linux does not
## allow nested chroots.
nixEnvOptions="--option sandbox false"
if [ -z $useBinaryCache ]; then
    nixEnvOptions="$nixEnvOptions --option binary-caches \"\""
fi
nixos-enter --root /mnt -c "/run/current-system/sw/bin/mv /resolv.conf /etc && \
  /run/current-system/sw/bin/nix-env $nixEnvOptions -p /nix/var/nix/profiles/system -f '<nixpkgs/nixos>' --set -A system"
informOk "...system configuration done"

informOk "activating final configuration..."
NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt \
  -c "/nix/var/nix/profiles/system/bin/switch-to-configuration boot"
informOk "...activation done"

chmod 755 /mnt

informOk "rebooting into the new system"
reboot --force
}

main "$@"
