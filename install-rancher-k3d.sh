#!/bin/bash -x

# Usage:
#  bash <(curl -sL LINKTORAWGIST) -r rancher.example.io -p 9091
#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -r rancherHostName -p rancherPort"
   echo -e "\t-r Rancher host name. Example: rancher.mydomain.tld"
   echo -e "\t-p The external port to access rancher. Example: 9001"
   exit 1 # Exit script after printing help
}

while getopts "r:p:" opt
do
   case "$opt" in
      r ) rancherHostName="$OPTARG" ;;
      p ) rancherPort="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$rancherHostName" ] || [ -z "$rancherPort" ]
then
   echo "Missing arguments";
   helpFunction
fi

if ! command -v k3d &> /dev/null
then
    echo "k3d could not be found, install it first"
    exit
fi

if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found, install it first"
    exit
fi

### 0. Install helm
apt install helm

### 1. Create a cluster with k3d that connects port 9091 to the loadbalancer provided by k3d
# Optionally install with more agents `--agents 3`
k3d cluster create rancher-cluster \
    --api-port 6550 \
    --servers 1 \
    --image rancher/k3s:latest \
    --port "$rancherPort":443@loadbalancer \
    --wait --verbose
k3d cluster list
date

### 2. Set up a kubeconfig so you can use kubectl in your current session
KUBECONFIG_FILE=~/.kube/rancher-cluster
k3d kubeconfig get rancher-cluster > $KUBECONFIG_FILE
chmod 600 $KUBECONFIG_FILE
export KUBECONFIG=$KUBECONFIG_FILE
kubectl get nodes

### 3. Install cert-manager with helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager
helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.6.1 \
    --set installCRDs=true --wait --debug
kubectl -n cert-manager rollout status deploy/cert-manager
date

### 4. Install the helm repos for rancher
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
kubectl create namespace cattle-system
helm install rancher rancher-latest/rancher \
    --namespace cattle-system \
    --version=2.6.1 \
    --set hostname="$rancherHostName" \
    --set bootstrapPassword=yayitworked \
    --no-deploy=traefik,servicelb
    --wait --debug
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get all,ing

echo "Rancher is now installed, visist https://$rancherHostName:$rancherPort"
echo "Rancher bootstrap password:"
echo https://"$rancherHostName":"$rancherPort"/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

### 5. Disable traefik
# ???
