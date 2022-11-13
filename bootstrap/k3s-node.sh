#!/usr/bin/env bash

set -e
G="\e[32m"
E="\e[0m"

if [ -z "$1" ]
  then
    echo -----------------------------------------------
    echo -e "Please provide your desired Rancher DNS name as part of the install command. eg: ./install.sh rancher.mydomain.tld."
    echo -----------------------------------------------
    exit 1
fi

if ! grep -q 'Ubuntu' /etc/issue
  then
    echo -----------------------------------------------
    echo "Not Ubuntu? Could not find Codename Ubuntu in lsb_release -a. Please switch to Ubuntu."
    echo -----------------------------------------------
    exit 1
fi

## Update OS
echo "Updating OS packages..."
sudo apt update > /dev/null 2>&1
sudo apt upgrade -y > /dev/null 2>&1

## Install Prereqs
echo "Installing Prereqs..."
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y \
apt-transport-https ca-certificates curl gnupg lsb-release fzf iptraf-ng\
software-properties-common haveged bash-completion  > /dev/null 2>&1

## Install Helm
echo "Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3  > /dev/null 2>&1
chmod 700 get_helm.sh  > /dev/null 2>&1
./get_helm.sh  > /dev/null 2>&1
rm ./get_helm.sh  > /dev/null 2>&1


## Install K3s
echo "Installing K3s..."
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.23.9+k3s1 sh -  > /dev/null 2>&1
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml  > /dev/null 2>&1
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chmod 0777 ~/.kube/config

## Wait for K3s to come online
echo "Waiting for K3s to come online...."
until [ $(kubectl get nodes|grep Ready | wc -l) = 1 ]; do echo -n "." ; sleep 2; done  > /dev/null 2>&1

## Install k8s console tools
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

echo export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" >> $HOME/.bashrc
echo export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" >> $HOME/.zshrc

kubectl krew install ns
kubectl krew install ctx
kubectl krew install tail

## Install Longhorn
echo "Deploying Longhorn on K3s..."
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' > /dev/null 2>&1
helm repo add longhorn https://charts.longhorn.io > /dev/null 2>&1
helm repo update > /dev/null 2>&1
helm upgrade longhorn longhorn/longhorn --namespace longhorn-system --create-namespace > /dev/null 2>&1

## Wait for Longhorn
echo "Waiting for Longhorn deployment to finish..."
until [ $(kubectl -n longhorn-system rollout status deploy/longhorn-ui|grep successfully | wc -l) = 1 ]; do echo -n "." ; sleep 2; done > /dev/null 2>&1
