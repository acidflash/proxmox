#!/bin/bash

# Fråga användaren hur många instanser som ska skapas
read -p "Hur många instanser vill du sätta upp? " num_instances

# Loopa genom antalet instanser som användaren har angett
for ((ID=1; ID<=num_instances; ID++))
do
  VMID="80$ID"
  (
    qm clone 8001 $VMID --name kubernetes0$ID --full
    qm set $VMID --name kubernetes0$ID
    qm set $VMID --net0 model=virtio,bridge=vmbr0
    qm set $VMID --ipconfig0 ip=192.168.34.$ID/24,gw=192.168.32.1
    qm set $VMID --memory 15021
    qm set $VMID --cores 4
    qm set $VMID --searchdomain labnat.local
    qm set $VMID --nameserver "192.168.30.53 192.168.230.53"
    qm set $VMID --tags Kubernetes,Prod
    qm set $VMID --onboot 1
    qm start $VMID
  ) &
  sleep 10
done

wait
