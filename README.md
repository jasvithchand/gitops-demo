# gitops-demo

A minimal Helm chart to experiment with ArgoCD GitOps.

## Repo structure

```
gitops-demo/
  argocd-app.yaml          # ArgoCD Application — connects this repo to your cluster
  nginx-app/
    Chart.yaml             # chart name + version
    values.yaml            # all config — EDIT THIS to trigger ArgoCD syncs
    templates/
      deployment.yaml      # K8s Deployment — reads from values.yaml
      service.yaml         # ClusterIP service (VIP)
      configmap.yaml       # nginx index.html — reads message from values.yaml
```

## Experiments to try

1. Change `replicaCount` in values.yaml → push → watch ArgoCD scale pods
2. Change `config.message` → push → curl nginx and see the new message
3. Change `image.tag` from 1.27 to 1.25 → push → watch rolling deploy
4. Delete a pod manually → ArgoCD selfHeal recreates it

## Setup

1. Edit `argocd-app.yaml` — replace YOUR_USERNAME with your GitHub username
2. Push this whole folder to your GitHub repo
3. Apply the ArgoCD app: `kubectl apply -f argocd-app.yaml`
4. Watch it sync: `argocd app get nginx-app`
