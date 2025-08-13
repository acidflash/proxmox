for ID in 1 2 3 4 5 6 7 8
do
VMID="80$ID"
qm stop $VMID
qm destroy $VMID
done
