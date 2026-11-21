# A/B-Bootskript
# rootpart: 2 = root_a, 3 = root_b (gesetzt von SWUpdate oder fw_setenv)

if test -z "${rootpart}"; then
    setenv rootpart 2
fi

echo "A/B: booting from ${devtype} ${devnum}:${rootpart}"

load ${devtype} ${devnum}:${rootpart} ${kernel_addr_r} /boot/zImage
load ${devtype} ${devnum}:${rootpart} ${fdt_addr_r} /boot/${fdtfile}

part uuid ${devtype} ${devnum}:${rootpart} rootuuid
setenv bootargs console=ttyS0,115200 root=PARTUUID=${rootuuid} rootwait

bootz ${kernel_addr_r} - ${fdt_addr_r}
