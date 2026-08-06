# Argo Rollout Setup Instructions

[Source](https://github.com/argoproj/argo-rollouts/blob/master/docs/getting-started.md)

## Setup

[Setup Guide](https://github.com/argoproj/argo-rollouts/blob/master/docs/installation.md)

### Controller Installation

```sh
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### Kubectl Plugin Installation

```sh
brew install argoproj/tap/kubectl-argo-rollouts
```
