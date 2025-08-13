#!/bin/bash

# Fråga användaren hur många instanser som ska skapas
read -p "Hur många instanser vill du ta bort? " num_instances

# Loopa genom antalet instanser som användaren har angett
for ((ID=1; ID<=num_instances; ID++))
do
  VMID="80$ID"
  (
    VMID="80$ID"
    qm stop $VMID
    qm destroy $VMID
  ) &
  sleep 3
done

wait
