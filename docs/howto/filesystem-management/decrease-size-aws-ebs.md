(howto:decrease-size-aws-ebs)=
# Resize an AWS EBS home directory volume down

AWS EBS volumes used for home directories support _increasing_ their size (see
[](howto:increase-disk-size)), but **not** _decreasing_ it. Therefore "decreasing the
size of an EBS volume" actually means creating a brand new, smaller volume, copying all
the files across from the larger volume, switching the hub over to it, and then deleting
the larger volume.

This document details how to proceed with that process.

```{warning}
This is a data migration on live home directories. Coordinate a **maintenance window** —
home directories are unavailable while the copy runs — and take a snapshot first.
```

```bash
export CLUSTER_NAME="<cluster-name>"
export HUB_NAME="<hub-name>"
export REGION="<aws-region>"          # e.g. us-west-2
export OLD_VOLUME_ID="<vol-old>"      # current (larger) volume; see the hub's values file
```

Take a safety snapshot of the existing volume before starting:

```bash
aws ec2 create-snapshot --region $REGION --volume-id $OLD_VOLUME_ID \
  --description "pre-shrink $HUB_NAME home-nfs" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=2i2c:hub-name,Value=$HUB_NAME}]"
```

## Create a new, smaller EBS volume

Navigate to the `terraform/aws` folder and open the relevant `projects/<cluster-name>.tfvars`
file. Add a **second** volume definition to `ebs_volumes` with a `name_suffix` and the
desired smaller size, leaving the original in place:

```
ebs_volumes = {
  "<hub>" = {                       # This first volume should already be present
    name_suffix = "<hub>",
    type        = "gp3",
    size        = <larger size in GiB>,
    tags        = { "2i2c:hub-name" : "<hub>" },
  },
  "<hub>-b" = {                      # This is the second volume we are adding
    name_suffix = "<hub>-b",        # Suffix avoids reusing the original's Name tag
    type        = "gp3",
    size        = <desired, smaller size in GiB>,
    tags        = { "2i2c:hub-name" : "<hub>" },
  },
}
```

Plan and apply, ensuring **only the new volume is created** and nothing else is affected,
then note the new volume's ID:

```bash
terraform plan  -var-file=projects/$CLUSTER_NAME.tfvars   # expect: 1 to add, 0 to change, 0 to destroy
terraform apply -var-file=projects/$CLUSTER_NAME.tfvars
terraform output ebs_volume_id_map                        # record the NEW volume id -> export NEW_VOLUME_ID=<vol-new>
```

```{note}
If NFS backups are enabled for this cluster (`enable_nfs_backup = true`), the new volume
is automatically tagged with `NFSBackup=true` and picked up by the Data Lifecycle Manager.
```

Open a PR and merge these changes so that other engineers cannot accidentally overwrite them.

## Migrate the data

On AWS, each hub's home directories live on a **single** EBS volume served by one
in-cluster `jupyterhub-home-nfs` server, so we copy at the block level by mounting both
the old and new volumes in a temporary pod. (This differs from the cloud-agnostic
[](migrate-data) flow, which copies between two running NFS servers.)

1. **Check there are no active users**, then scale the NFS server down so the old volume
   detaches (EBS volumes are single-attach):

   ```bash
   kubectl --namespace $HUB_NAME get pods -l "component=singleuser-server"   # expect none
   kubectl --namespace $HUB_NAME scale deploy storage-quota-home-nfs --replicas=0
   ```

1. **Create a copy pod** that mounts the old volume at `/old` and the new volume at `/new`
   and rsyncs across. Save as `copy.yaml`, substituting `$OLD_VOLUME_ID`, `$NEW_VOLUME_ID`
   and `$HUB_NAME`:

   ```yaml
   apiVersion: v1
   kind: PersistentVolume
   metadata: { name: migrate-old }
   spec:
     capacity: { storage: 1M }
     accessModes: [ReadWriteOnce]
     persistentVolumeReclaimPolicy: Retain
     storageClassName: ""
     csi: { driver: ebs.csi.aws.com, fsType: xfs, volumeHandle: OLD_VOLUME_ID }
   ---
   apiVersion: v1
   kind: PersistentVolume
   metadata: { name: migrate-new }
   spec:
     capacity: { storage: 1M }
     accessModes: [ReadWriteOnce]
     persistentVolumeReclaimPolicy: Retain
     storageClassName: ""
     csi: { driver: ebs.csi.aws.com, fsType: xfs, volumeHandle: NEW_VOLUME_ID }
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: { name: migrate-old, namespace: HUB_NAME }
   spec: { accessModes: [ReadWriteOnce], storageClassName: "", volumeName: migrate-old, resources: { requests: { storage: 1M } } }
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: { name: migrate-new, namespace: HUB_NAME }
   spec: { accessModes: [ReadWriteOnce], storageClassName: "", volumeName: migrate-new, resources: { requests: { storage: 1M } } }
   ---
   apiVersion: v1
   kind: Pod
   metadata: { name: home-migrate, namespace: HUB_NAME }
   spec:
     nodeSelector: { 2i2c/hub-name: HUB_NAME }
     tolerations:
       - { key: hub.jupyter.org/dedicated, operator: Equal, value: user, effect: NoSchedule }
       - { key: hub.jupyter.org_dedicated, operator: Equal, value: user, effect: NoSchedule }
     restartPolicy: Never
     containers:
       - name: copy
         image: public.ecr.aws/docker/library/alpine:3.20
         command: ["sh","-c","apk add --no-cache rsync && rsync -aHAX --info=progress2 /old/ /new/ && echo COPY-DONE"]
         volumeMounts:
           - { name: old, mountPath: /old }
           - { name: new, mountPath: /new }
     volumes:
       - { name: old, persistentVolumeClaim: { claimName: migrate-old } }
       - { name: new, persistentVolumeClaim: { claimName: migrate-new } }
   ```

   ```bash
   kubectl apply -f copy.yaml
   kubectl logs --namespace $HUB_NAME home-migrate -f      # wait for "COPY-DONE"
   kubectl delete -f copy.yaml                             # Retain policy keeps both volumes safe
   ```

   ```{note}
   `rsync -aHAX` preserves ownership, permissions, ACLs and extended attributes. The new
   volume is formatted XFS automatically by the CSI driver (`fsType: xfs`) on first attach,
   so `/new` is mountable and empty, ready to receive the copy.
   ```

## Switch the hub to the new volume

1. **Update the volume ID** in `config/clusters/$CLUSTER_NAME/$HUB_NAME.values.yaml`:

   ```yaml
   jupyterhub-home-nfs:
     eks:
       volumeId: <new-volume-id>
   ```

1. **Verify the reclaim policy is `Retain`** (it is by default for these volumes), so
   deleting the old PV does not delete the underlying volume:

   ```bash
   kubectl get pv $HUB_NAME-storage-quota-home-nfs -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'
   ```

1. **Delete the old home-nfs PV and PVC** so the chart recreates them against the new
   volume (PVs are immutable, so they must be recreated):

   ```bash
   kubectl --namespace $HUB_NAME delete pvc storage-quota-home-nfs
   kubectl delete pv $HUB_NAME-storage-quota-home-nfs
   ```

1. **Redeploy the hub** (this also scales the NFS server back up, on the new volume):

   ```bash
   deployer deploy $CLUSTER_NAME $HUB_NAME
   ```

1. **Verify** the new size and that the data is present:

   ```bash
   POD=$(kubectl --namespace $HUB_NAME get po | grep storage-quota | awk '{print $1}')
   kubectl --namespace $HUB_NAME exec $POD -c nfs-server -- df -h /export   # new (smaller) size
   kubectl --namespace $HUB_NAME exec $POD -c nfs-server -- ls /export      # user home dirs present
   ```

   Start a test user server and confirm files are intact.

Open and merge a PR with the values change so that other engineers cannot accidentally
overwrite it.

## Decommission the old volume

Only once you have verified the hub is healthy on the new volume:

Back in `terraform/aws/projects/<cluster-name>.tfvars`, delete the **original** (larger)
volume definition from `ebs_volumes`, keeping only the new one.

You also need to temporarily comment out the [`lifecycle` block in `terraform/aws/ebs-volumes.tf`](https://github.com/2i2c-org/infrastructure/blob/HEAD/terraform/aws/ebs-volumes.tf)
(`prevent_destroy = true`), otherwise the old volume is prevented from being destroyed.

Plan and apply, ensuring **only the old volume will be destroyed**:

```bash
terraform plan  -var-file=projects/$CLUSTER_NAME.tfvars   # confirm: only the OLD volume is destroyed
terraform apply -var-file=projects/$CLUSTER_NAME.tfvars
```

```{warning}
Double-check the plan destroys **only** the old volume before applying — a mistake here
deletes home directories.
```

Open and merge a PR with the `.tfvars` change — but **DO NOT** commit the `ebs-volumes.tf`
file; discard those changes.

Keep the safety snapshot for a few days, then delete it. Congratulations — you have
decreased the size of an AWS EBS home directory volume!
