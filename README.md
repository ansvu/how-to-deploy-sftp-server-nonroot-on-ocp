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
+ oc get svc
NAME          TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
sftp-noroot   NodePort   172.30.79.100   <none>        2022:30024/TCP   2d21h
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
- **Edit PV to change RWO to RWX (ReadWriteOnce --> ReadWriteMany)**
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
## Deploy SFTP Server 
- **For OCP, add anyuid to SCC ServiceAcount and Namespace**
```diff
+ oc adm policy add-scc-to-user anyuid -z noroot-sa system:serviceaccount:sftp-noroot:noroot-sa
```
**Note: noroot-sa=sa and sftp-noroot=ns**

- **Start Deploy SFTP Server**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: sftp-noroot
  name: sftp-noroot-cm
  namespace: sftp-noroot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sftp-noroot
  template:
    metadata:
      labels:
        app: sftp-noroot
    spec:
      serviceAccountName: noroot-sa            
      securityContext:
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - image: quay.io/avu0/sftp-noroot:v7
        imagePullPolicy: IfNotPresent
        name: sftp-noroot
        ports:
        - containerPort: 2022
          name: ssh
          protocol: TCP
        volumeMounts:
        - mountPath: /opt/ssh
          name: sftp-ava-ssh
        - mountPath: /home/ava/sftp-data
          name: sftp-femto-ava          
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      volumes:
      - configMap:
          defaultMode: 384
          name: sftp-ava-ssh
        name: sftp-ava-ssh
      - name: sftp-femto-ava
        persistentVolumeClaim:
          claimName: femto-data-store
```
```diff
+ oc apply -f create-sftpnoroot-deploy-cm.yaml
+ oc get po
NAME                              READY   STATUS    RESTARTS   AGE
sftp-noroot-cm-5c95546fd5-6sfws   1/1     Running   0          112m
```

## Start SFTP Server Testing
- **Checking SSHD Service running as normal user**
```bash
oc exec -it sftp-noroot-cm-5c95546fd5-6sfws bash
bash-5.1$ ps -ef
PID   USER     TIME  COMMAND
    1 ava       0:00 sshd: /usr/sbin/sshd -D -f /opt/ssh/sshd_config -E /tmp/sshd.log [listener] 0 of 10-100 startups
   15 ava       0:00 bash
   22 ava       0:00 ps -ef

df -h
Filesystem                Size      Used Available Use% Mounted on
overlay                 446.6G     92.5G    354.1G  21% /
/dev/sdb4               446.6G     92.5G    354.1G  21% /opt/ssh
tmpfs                    93.8G     79.4M     93.7G   0% /run/secrets
/dev/sdc                439.1G    119.2M    439.0G   0% /home/ava/sftp-data

bash-5.1$ ls -lrt /opt/ssh/
total 0
lrwxrwxrwx    1 root     ava             18 Jul 11 16:36 sshd_config -> ..data/sshd_config
lrwxrwxrwx    1 root     ava             27 Jul 11 16:36 ssh_host_rsa_key.pub -> ..data/ssh_host_rsa_key.pub
lrwxrwxrwx    1 root     ava             23 Jul 11 16:36 ssh_host_rsa_key -> ..data/ssh_host_rsa_key
lrwxrwxrwx    1 root     ava             31 Jul 11 16:36 ssh_host_ed25519_key.pub -> ..data/ssh_host_ed25519_key.pub
lrwxrwxrwx    1 root     ava             27 Jul 11 16:36 ssh_host_ed25519_key -> ..data/ssh_host_ed25519_key
bash-5.1$ ls -lrt /home/ava/sftp-data/
total 20
drwxrws---    2 root     ava          16384 Jul  8 22:31 lost+found
-rw-r--r--    1 ava      ava            227 Jul 11 16:37 pvc.yaml
```
- **Start SFTP upload files testing**
```bash
sftp -P 30024 ava@192.168.24.111
ava@192.168.24.111's password: 
Connected to ava@192.168.24.111.

sftp> cd sftp-data/
sftp> put oc-4.9.12-linux.tar.gz 
Uploading oc-4.9.12-linux.tar.gz to /home/ava/sftp-data/oc-4.9.12-linux.tar.gz
oc-4.9.12-linux.tar.gz     100%   47MB   9.6MB/s   00:06

sftp> ls -lrt
drwxrws---    2 root     ava         16384 Jul  8 22:31 lost+found
-rw-r--r--    1 ava      ava           227 Jul 11 16:37 pvc.yaml
-rw-r--r--    1 ava      ava      49412507 Jul 11 18:36 oc-4.9.12-linux.tar.gz
```

## Limitations When Run SSHD service non-root User

- **Only user to run SSHD service can be used as sftp***
So if we create another user it wont allow it to use to DO sftp or authenticate
As mentioned here from this link https://www.golinuxcloud.com/run-sshd-as-non-root-user-without-sudo/
I also created another from Dockerfile with ava user is used to run sshd, I also got denied as above link had stated as well.

- **Can not used entrypoint script to create user based on configmap**
The problem is if we create user using entrypoint, we can not create that user since useradd or groupadd wont allow to update to /etc/group or /etc/passwd. 
So it means, we can only create user/setpasswd during Dockerfile image build!!!

- **Another Limitation is can not set chpasswd -e for this user***
It allowed to change/update with encrypted password but when using sftp to upload/authenticate, it got denied, from /etc/shadow, the contents shown weird

**Note: if someone can advice and have WA, that would be great!!!!**

