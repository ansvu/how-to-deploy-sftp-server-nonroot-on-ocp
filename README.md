# how-to-deploy-sftp-server-nonroot-on-ocp
The purpose of this repository is to show how to deploy sftp server on normal user(non-root) on OpenShift Kubernetes platform.
The steps are about to show is based on this github https://github.com/atmoz/sftp. To make this sftp server setup to work, sshd service must run as specific user (not with root privilege) and other files that associates to it. User can mount those ssh keys and sshd_config to configmap, and also mount their own PVC to specific directory where sftp files, configuration and logs can be stored to this PVC claim, so when POD is restarted, those files are still intact.

Let get started.


## Build Dockerfile image for sftp server using podman
```yaml
Dockerfile:
FROM atmoz/sftp:alpine
EXPOSE 2022

RUN addgroup -S -g 1000 ava && adduser -S -u 1000 ava -G ava -h /home/ava \
    && echo "ava:Avasys!1" | chpasswd \
    && rm /usr/local/bin/create-sftp-user /entrypoint

USER 1000
ENTRYPOINT /usr/sbin/sshd -D -f /opt/ssh/sshd_config  -E /tmp/sshd.log \
```
```diff
+ podman build -t sftp-noroot:v1 -f ./Dockerfile
+ podman tag sftp-noroot:v1 quay.io/xxx/sftp-noroot:v1
+ podman push quay.io/xxx/sftp-noroot:v1
- Note: xxx is user quay username or other form of registry-server from your labs
```
## Create Namespace, ServiceAccount and SVC for NodePort
```diff
+ oc create namespace sftp-noroot
+ oc create sa noroot-sa
```
**sftp-noroot-svc.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: sftp-noroot
  namespace: sftp-noroot
spec:
  ports:
  - name: 2022-tcp
    nodePort: 30024
    port: 2022
    protocol: TCP
    targetPort: 2022
  selector:
    app: sftp-noroot
  type: NodePort
```
```diff
+ oc apply -f sftp-noroot-svc.yaml
```

## Create SFTP Server Configmap that contain the SSH Keys and sshd_config files
Note: 

- **Create SSH Keys**
```diff
+ ssh-keygen -t ed25519 -f ssh_host_ed25519_key < /dev/null
+ ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key < /dev/null
- ---------------------------------------------------------------
-rw-r--r--. 1 xxx xxx  100 Jul 11 12:56 ssh_host_ed25519_key.pub
-rw-------. 1 xxx xxx  411 Jul 11 12:56 ssh_host_ed25519_key
-rw-r--r--. 1 xxx xxx  744 Jul 11 12:56 ssh_host_rsa_key.pub
-rw-------. 1 xxx xxx 3381 Jul 11 12:56 ssh_host_rsa_key
+ ---------------------------------------------------------------
- Note: hit enter->enter for passphase screen 
```
- **Create SFTP Server Configmap**
```yaml
apiVersion: v1
data:
  ssh_host_ed25519_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBypIA/JgbH6tlkfFMK4D6CNJlXrEzRKPWgQYrMDW1rsQAAAJgZO+JRGTvi
    .............
    .............
    mVesTNEo9aBBiswNbWuxAAAAEmF2dUBhdnUucmVtb3RlLmNzYgECAw==
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_ed25519_key.pub: |
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHKkgD8mBsfq2WR8UwrgPoI0mVesTNEo9aBBiswNbWux xxxxxxxxxxxxxxxxx
  ssh_host_rsa_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
    NhAAAAAwEAAQAAAgEA8hiQQIvis4/ur/tBOHfQ9/5Sn/URZKdhvP7zSb5trLdekDcss9sr
    oaHcozMI2zIDxVgkA96fCJvNOaxi5MQoMpQeQTSVGt0GvgoIY/W+y4PJwfDu4dKozN+ScN
    ikA4zbbYU4x3vNM+S/IZAjC15NY3dcjuNOowzxTTNFPuYKKw4HOLhMB/2VjiSZRTZ2nVvd
    ..................
    ..................
    ..................
    TTGefPih42cAAAASYXZ1QGF2dS5yZW1vdGUuY3NiAQ==
    -----END OPENSSH PRIVATE KEY-----
  ssh_host_rsa_key.pub: |
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDyGJBAixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  sshd_config: |
    Protocol 2
    HostKey /opt/ssh/ssh_host_ed25519_key
    HostKey /opt/ssh/ssh_host_rsa_key
    UseDNS no
    PermitRootLogin no
    X11Forwarding no
    AllowTcpForwarding no
    Subsystem sftp internal-sftp
    ForceCommand internal-sftp
    LogLevel DEBUG3
    Port 2022
    PidFile /opt/ssh/sshd.pid
    ChallengeResponseAuthentication no
    UsePAM yes
kind: ConfigMap
metadata:
  name: sftp-ava-ssh
  namespace: sftp-noroot
```
```diff
+ oc apply -f sftp-ava-key-conf-cm.yaml
``` 

## Create Local Storage, PV and PVC for user sftp-data directory
**Note:** I am testing on OCP SNO so I need to create LSO and PVC so we can create PVC for sftp data mount points

if you have ODF install on hub-cluster or multi-clusters, then use StorageClass from cephfs to create PVC.
 so /dev/sdc is your local disk that from your SNO or worker node.
 
- **Create LSO (Local Storage Operator)**

```yaml
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: fs
  namespace: openshift-local-storage
spec:
  logLevel: Normal
  managementState: Managed
  storageClassDevices:
    - devicePaths:
        - /dev/sdc
      fsType: ext4
      storageClassName: local-storage
      volumeMode: Filesystem
```
```diff
+ oc apply -f fs-pv-sdc.yaml
```
```bash
+ oc get po -n openshift-local-storage
NAME                                      READY   STATUS    RESTARTS        AGE
diskmaker-manager-sk27k                   2/2     Running   0               2d19h
local-storage-operator-69859b55fd-dg5rt   1/1     Running   11 (3d6h ago)   10d
+ oc get pv
NAME                CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                          STORAGECLASS    REASON   AGE
local-pv-ad6ab568   447Gi      RWO            Delete           Bound    sftp-noroot/femto-data-store   local-storage            2d19h
```
- **Patch storageclass local-storage to "storageclass.kubernetes.io/is-default-class"**
```diff
+ oc patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
+ oc get sc
NAME                      PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-storage (default)   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  2d19h
```
- ** Edit PV to change RWO to RWX (ReadWriteOnce --> ReadWriteMany)**
```diff
+ oc edit pv local-pv-ad6ab568
spec:
  accessModes:
  - ReadWriteOnce-->ReadWriteMany
:wq
```
- **Create PVC for sftp-data mount directory**
**Note:** if you have StorageClass from ODF other SC, uncomment out last line and give your SC name 
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: femto-data-store
spec:
  accessModes:
  - ReadWriteMany
  volumeMode: Filesystem 
  resources:
    requests:
      storage: 447Gi 
  #storageClassName: local-storage
```
```diff
+ oc apply -f pvc.yaml
+oc get pvc
NAME               STATUS   VOLUME              CAPACITY   ACCESS MODES   STORAGECLASS    AGE
femto-data-store   Bound    local-pv-ad6ab568   447Gi      RWX            local-storage   2d19h
```

