# Apply the ArgoCD manifests to install in the cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Setup an application to sync changes in the developer-platform repo
kubectl apply -f argocd-bootstrap.yaml
