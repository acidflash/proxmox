for ID in 1 2 3 4 5 6 7 8 9
do
VMID="80$ID"
qm clone 8001 $VMID --name kubernetes0$ID --full
qm set $VMID --name kubernetes0$ID
qm set $VMID --net0 model=virtio,bridge=vmbr0
qm set $VMID --ipconfig0 ip=192.168.230.6$ID/24,gw=192.168.230.1
qm set $VMID --memory 8192
qm set $VMID --cores 4
qm set $VMID --searchdomain labnat.local
qm set $VMID --nameserver 192.168.230.53
qm set $VMID --tags Kubernetes,Prod
qm set $VMID --onboot 1
qm start $VMID
done
