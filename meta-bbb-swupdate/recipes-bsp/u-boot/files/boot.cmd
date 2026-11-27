# A/B-Bootskript
# rootpart: 2 = root_a, 3 = root_b (gesetzt von SWUpdate oder fw_setenv)

if test -z "${rootpart}"; then
    setenv rootpart 2
fi

if test -z "${ab_limit}"; then
    setenv ab_limit 3
fi

if test -z "${ab_count}"; then
    setenv ab_count 0
fi

if test "${ustate}" = "1"; then
    setexpr ab_count ${ab_count} + 1
    if test "${ab_count}" -gt "${ab_limit}"; then
        if test "${rootpart}" = "2"; then
            setenv rootpart 3
        else
            setenv rootpart 2
        fi
        echo "A/B: ab_count ${ab_count} > ab_limit ${ab_limit}, switching to rootpart ${rootpart}"
        setenv ab_count 0
        setenv ustate 3
    fi
    saveenv
fi

echo "A/B: booting from ${devtype} ${devnum}:${rootpart}"

load ${devtype} ${devnum}:${rootpart} ${kernel_addr_r} /boot/zImage
load ${devtype} ${devnum}:${rootpart} ${fdt_addr_r} /boot/${fdtfile}

part uuid ${devtype} ${devnum}:${rootpart} rootuuid

# panic=5: nach einer Kernel-Panic neu starten (Kernel-Vorgabe: für immer warten)
# omap_wdt.early_enable=1: Watchdog von U-Boot weiterlaufen lassen, der Treiber
#   schaltet ihn sonst beim Laden ab
setenv bootargs console=ttyS0,115200 panic=5 omap_wdt.early_enable=1 root=PARTUUID=${rootuuid} rootwait

bootz ${kernel_addr_r} - ${fdt_addr_r}
