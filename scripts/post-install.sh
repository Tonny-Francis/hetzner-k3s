#!/bin/bash
set -e

# Define o kubeconfig gerado pelo hetzner-k3s
kubectl config unset current-context

export KUBECONFIG="../k3s/kubeconfig"

echo "🔧 Verificando cluster..."
kubectl cluster-info
kubectl get nodes

echo "🔧 Instalando NGINX Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.nodeSelector.ingress=allow \
    --set controller.replicaCount=6 \
    --set controller.service.annotations."load-balancer\.hetzner\.cloud/network-zone"=eu-central

echo "✅ NGINX Ingress instalado!"

# Cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set nodeSelector.node-role=tools

echo "✅ Cert-Manager instalado!"

echo "🔧 Aguardando cert-manager estar pronto..."
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=120s deployment/cert-manager-webhook -n cert-manager

# Verificar se ClusterIssuer já existe
if kubectl get clusterissuer letsencrypt-production &>/dev/null; then
  echo "⚠️  ClusterIssuer 'letsencrypt-production' já existe!"
  read -p "Deseja reconfigurar? (s/N): " RECONFIG
  if [[ ! "$RECONFIG" =~ ^[sS]$ ]]; then
    echo "⏭️  Pulando configuração do ClusterIssuer..."
  else
    echo "🔧 Reconfigurando Cloudflare e ClusterIssuer..."
    read -p "Digite seu email: " EMAIL
    read -sp "Digite sua Cloudflare API Key: " CLOUDFLARE_API_KEY
    echo

    kubectl create secret generic cloudflare-secret \
      --from-literal=api-key="$CLOUDFLARE_API_KEY" \
      --namespace=cert-manager \
      --dry-run=client -o yaml | kubectl apply -f -

    sed "s/YOUR_EMAIL/$EMAIL/g" cert-manager/clusterIssuer.yaml | kubectl apply -f -
    echo "✅ ClusterIssuer reconfigurado!"
  fi
else
  echo "🔧 Configurando Cloudflare para cert-manager..."
  read -p "Digite seu email: " EMAIL
  read -sp "Digite sua Cloudflare API Key: " CLOUDFLARE_API_KEY
  echo

  kubectl create secret generic cloudflare-secret \
    --from-literal=api-key="$CLOUDFLARE_API_KEY" \
    --namespace=cert-manager \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "🔧 Aplicando ClusterIssuer..."
  sed "s/YOUR_EMAIL/$EMAIL/g" cert-manager/clusterIssuer.yaml | kubectl apply -f -
  echo "✅ ClusterIssuer configurado!"
fi

# Rancher Import
echo ""
read -p "🐮 Deseja importar este cluster no Rancher? (s/N): " RANCHER_IMPORT
if [[ "$RANCHER_IMPORT" =~ ^[sS]$ ]]; then
  echo "🔧 Importando cluster no Rancher..."
  echo "ℹ️  Acesse o Rancher e copie a URL de importação do cluster"
  echo "ℹ️  Exemplo: https://rancher.example.com/v3/import/xxxxx.yaml"
  read -p "Cole a URL do YAML de importação: " RANCHER_URL
  
  if [[ -n "$RANCHER_URL" ]]; then
    echo "🔧 Aplicando manifesto do Rancher..."
    kubectl apply -f "$RANCHER_URL"
    echo "✅ Cluster importado no Rancher!"
    echo "ℹ️  Aguarde alguns minutos para o cluster aparecer no Rancher"
  else
    echo "⚠️  URL não fornecida. Pulando importação do Rancher."
  fi
else
  echo "⏭️  Pulando importação do Rancher..."
fi

echo "🎉 Post-install concluído!"