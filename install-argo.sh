##########################################################
# Using this script:
#
# This script assumes you have the following installed
# 1. kubectl
# 2. krew and its view-secret plugin
# 3. jq
# 4. gh (Github cli)
#
# Before running the script ensure you have logged in to
# github with the gh tool.
#
# `gh auth login`
#
##########################################################


# Create the argocd namespace if it does not already exist
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Apply the ArgoCD manifests to install in the cluster
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Setup an application to sync changes in the developer-platform repo
kubectl apply -f bootstrap.yaml

# Create the provider-argocd user.
# This will be used to authenticate the argocd crossplane provider.
kubectl patch configmap/argocd-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"accounts.provider-argocd":"apiKey"}}'

kubectl patch configmap/argocd-rbac-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"policy.csv":"g, provider-argocd, role:admin"}}'

# Setup some variables for working with argocd over a port-forward
ARGOCD_ADMIN_SECRET=$(kubectl view-secret argocd-initial-admin-secret -n argocd -q)
LOCAL_PORT=8443
REMOTE_PORT=443

# Start the port-forward to interact with the argo repo server
kubectl -n argocd port-forward svc/argocd-server $LOCAL_PORT:$REMOTE_PORT > /dev/null 2>&1 &
PID=$!

# kill the port-forward regardless of how this script exits
trap '{
    echo killing $PID
    kill $PID
}' EXIT

# wait for $LOCAL_PORT to become available
while ! nc -vz localhost $LOCAL_PORT > /dev/null 2>&1 ; do
    echo Waiting for port...
    sleep 0.1
done

# Create a session token for interacting with ARGOCD. Note that you
# can't use this token directly as it will expire. Instead we exchange
# it for a permanent API Token below.
ARGOCD_ADMIN_TOKEN=$(curl -s -X POST -k -H "Content-Type: application/json" --data '{"username":"admin","password":"'"$ARGOCD_ADMIN_SECRET"'"}' "https://localhost:$LOCAL_PORT/api/v1/session" | jq -r .token)

# Exchange the session token for an API token
ARGOCD_PROVIDER_USER="provider-argocd"
ARGOCD_TOKEN=$(curl -s -X POST -k -H "Authorization: Bearer $ARGOCD_ADMIN_TOKEN" -H "Content-Type: application/json" "https://localhost:$LOCAL_PORT/api/v1/account/$ARGOCD_PROVIDER_USER/token" | jq -r .token)

# Create the crossplane-system namespace if it does not already exist
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Create a kubernetes secret with the argocd token. This will be used as a
# provider-config in crossplane
kubectl create secret generic argocd-credentials -n crossplane-system --from-literal=authToken="$ARGOCD_TOKEN"

# Retrieve the github token associated with gh. This assumes you have gh installed
# and have run gh auth login
GITHUB_TOKEN=$(gh auth token)
GITHUB_OWNER=cabewaldrop # Replace with github username if not cabewaldrop

# Create a kubernetes secret with the Github credentials. This will be used as
# part of a provider-config in crossplane
kubectl create secret generic github-credentials -n crossplane-system --from-literal=credentials="{\"token\":\"${GITHUB_TOKEN}\",\"owner\":\"${GITHUB_OWNER}\"}"
