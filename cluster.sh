#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# LinkPulse Local Cluster Manager
# Usage:
#   ./cluster.sh down    → scale everything to 0 (cool down your Mac)
#   ./cluster.sh up      → restore everything back to running
#   ./cluster.sh status  → see what's running right now
#   ./cluster.sh restart → down then up
# ─────────────────────────────────────────────────────────────────────────────

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()    { echo -e "${BLUE}[linkpulse]${NC} $1"; }
success(){ echo -e "${GREEN}[linkpulse]${NC} $1"; }
warn()   { echo -e "${YELLOW}[linkpulse]${NC} $1"; }
error()  { echo -e "${RED}[linkpulse]${NC} $1"; }

# ─── DOWN ────────────────────────────────────────────────────────────────────
down() {
  log "Scaling down LinkPulse local cluster..."
  echo ""

  # ── StatefulSets in data namespace ──
  log "Scaling down StatefulSets (postgres, redis)..."
  kubectl scale statefulset postgres --replicas=0 -n data 2>/dev/null && \
    success "  postgres scaled to 0" || warn "  postgres not found (skipping)"
  kubectl scale statefulset redis --replicas=0 -n data 2>/dev/null && \
    success "  redis scaled to 0" || warn "  redis not found (skipping)"

  # ── ArgoCD ──
  log "Scaling down ArgoCD..."
  kubectl scale deployment argocd-server               --replicas=0 -n argocd 2>/dev/null
  kubectl scale deployment argocd-repo-server          --replicas=0 -n argocd 2>/dev/null
  kubectl scale deployment argocd-applicationset-controller --replicas=0 -n argocd 2>/dev/null
  kubectl scale deployment argocd-notifications-controller  --replicas=0 -n argocd 2>/dev/null
  kubectl scale deployment argocd-dex-server           --replicas=0 -n argocd 2>/dev/null
  kubectl scale deployment argocd-redis                --replicas=0 -n argocd 2>/dev/null
  kubectl scale statefulset argocd-application-controller --replicas=0 -n argocd 2>/dev/null
  success "  ArgoCD scaled to 0"

  # ── Prometheus + Grafana ──
  log "Scaling down Prometheus + Grafana..."
  kubectl scale deployment prometheus-grafana                          --replicas=0 -n monitoring 2>/dev/null
  kubectl scale deployment prometheus-kube-prometheus-operator         --replicas=0 -n monitoring 2>/dev/null
  kubectl scale deployment prometheus-kube-state-metrics               --replicas=0 -n monitoring 2>/dev/null
  kubectl scale statefulset prometheus-prometheus-kube-prometheus-prometheus --replicas=0 -n monitoring 2>/dev/null
  success "  Prometheus + Grafana scaled to 0"

  # ── NGINX Ingress ──
  log "Scaling down NGINX Ingress..."
  kubectl scale deployment ingress-nginx-controller --replicas=0 -n ingress-nginx 2>/dev/null && \
    success "  NGINX Ingress scaled to 0" || warn "  NGINX Ingress not found (skipping)"

  # ── nginx-app (gitops demo) ──
  log "Scaling down nginx-app..."
  kubectl scale deployment nginx-app --replicas=0 -n default 2>/dev/null && \
    success "  nginx-app scaled to 0" || warn "  nginx-app not found (skipping)"

  # ── Future services namespace (safe to run even if not created yet) ──
  if kubectl get namespace services &>/dev/null; then
    log "Scaling down services namespace..."
    kubectl scale deployment --all --replicas=0 -n services 2>/dev/null
    success "  services namespace scaled to 0"
  fi

  # ── Future platform namespace (kong, istio, rabbitmq etc) ──
  if kubectl get namespace platform &>/dev/null; then
    log "Scaling down platform namespace..."
    kubectl scale deployment --all --replicas=0 -n platform 2>/dev/null
    success "  platform namespace scaled to 0"
  fi

  echo ""
  success "All workloads scaled down. Your Mac should cool down shortly."
  warn "Note: kube-system control plane pods stay running — Kubernetes itself needs them."
  warn "      They use minimal CPU when idle."
  echo ""
  log "To resume: ./cluster.sh up"
}

# ─── UP ──────────────────────────────────────────────────────────────────────
up() {
  log "Restoring LinkPulse local cluster..."
  echo ""

  # ── ArgoCD first — it manages everything else ──
  log "Starting ArgoCD..."
  kubectl scale deployment argocd-server               --replicas=1 -n argocd 2>/dev/null
  kubectl scale deployment argocd-repo-server          --replicas=1 -n argocd 2>/dev/null
  kubectl scale deployment argocd-applicationset-controller --replicas=1 -n argocd 2>/dev/null
  kubectl scale deployment argocd-notifications-controller  --replicas=1 -n argocd 2>/dev/null
  kubectl scale deployment argocd-dex-server           --replicas=1 -n argocd 2>/dev/null
  kubectl scale deployment argocd-redis                --replicas=1 -n argocd 2>/dev/null
  kubectl scale statefulset argocd-application-controller --replicas=1 -n argocd 2>/dev/null
  success "  ArgoCD starting..."

  # ── StatefulSets ──
  log "Starting StatefulSets (postgres, redis)..."
  kubectl scale statefulset postgres --replicas=1 -n data 2>/dev/null && \
    success "  postgres starting..." || warn "  postgres not found (skipping)"
  kubectl scale statefulset redis --replicas=1 -n data 2>/dev/null && \
    success "  redis starting..." || warn "  redis not found (skipping)"

  # ── NGINX Ingress ──
  log "Starting NGINX Ingress..."
  kubectl scale deployment ingress-nginx-controller --replicas=1 -n ingress-nginx 2>/dev/null && \
    success "  NGINX Ingress starting..." || warn "  NGINX Ingress not found (skipping)"

  # ── nginx-app ──
  log "Starting nginx-app..."
  kubectl scale deployment nginx-app --replicas=1 -n default 2>/dev/null && \
    success "  nginx-app starting..." || warn "  nginx-app not found (skipping)"

  # ── Prometheus + Grafana (comment this out if you want faster startup) ──
  log "Starting Prometheus + Grafana..."
  kubectl scale deployment prometheus-grafana                          --replicas=1 -n monitoring 2>/dev/null
  kubectl scale deployment prometheus-kube-prometheus-operator         --replicas=1 -n monitoring 2>/dev/null
  kubectl scale deployment prometheus-kube-state-metrics               --replicas=1 -n monitoring 2>/dev/null
  kubectl scale statefulset prometheus-prometheus-kube-prometheus-prometheus --replicas=1 -n monitoring 2>/dev/null
  success "  Prometheus + Grafana starting..."

  # ── Future namespaces ──
  if kubectl get namespace services &>/dev/null; then
    log "Starting services namespace..."
    # Services are managed by ArgoCD — trigger a sync instead of manual scale
    argocd app sync --all 2>/dev/null || warn "  ArgoCD not ready yet — services will sync automatically"
  fi

  echo ""
  success "All workloads scaling up. Give it 60-90 seconds for everything to be Ready."
  echo ""
  log "Watch progress:  kubectl get pods -A --field-selector=status.phase!=Running"
  log "Quick status:    ./cluster.sh status"
  echo ""

  # Wait and show final status
  log "Waiting 30s for pods to start..."
  sleep 30
  status
}

# ─── STATUS ──────────────────────────────────────────────────────────────────
status() {
  echo ""
  log "Current cluster state:"
  echo ""

  # Count pods by phase
  RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || true)
  PENDING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Pending" || true)
  NOT_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | grep -v "^$" | wc -l | tr -d ' ' || true)

  echo -e "  ${GREEN}Running:${NC}     $RUNNING pods"
  echo -e "  ${YELLOW}Pending:${NC}     $PENDING pods"
  echo -e "  ${RED}Not Ready:${NC}   $((NOT_RUNNING - PENDING)) pods"
  echo ""

  # Per-namespace summary
  for ns in kube-system argocd monitoring data ingress-nginx default services platform; do
    if kubectl get namespace $ns &>/dev/null; then
      TOTAL=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
      READY=$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep -c "Running" || true)
      if [ "$TOTAL" -eq 0 ]; then
        echo -e "  ${YELLOW}$ns${NC}: scaled down (0 pods)"
      elif [ "$READY" -eq "$TOTAL" ]; then
        echo -e "  ${GREEN}$ns${NC}: $READY/$TOTAL Running ✓"
      else
        echo -e "  ${YELLOW}$ns${NC}: $READY/$TOTAL Running (some starting...)"
      fi
    fi
  done

  echo ""

  # StatefulSet data check
  if kubectl get namespace data &>/dev/null; then
    PG=$(kubectl get pod postgres-0 -n data --no-headers 2>/dev/null | awk '{print $3}' || echo "scaled down")
    RD=$(kubectl get pod redis-0 -n data --no-headers 2>/dev/null | awk '{print $3}' || echo "scaled down")
    echo -e "  postgres-0:  ${BLUE}$PG${NC}"
    echo -e "  redis-0:     ${BLUE}$RD${NC}"
    echo ""
  fi

  # Port-forward reminder
  echo -e "  ${BLUE}Port forwards (run in separate terminals when needed):${NC}"
  echo "  ArgoCD:     kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  Grafana:    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
  echo "  Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  echo ""
}

# ─── RESTART ─────────────────────────────────────────────────────────────────
restart() {
  down
  echo ""
  log "Waiting 10s before bringing back up..."
  sleep 10
  up
}

# ─── ENTRY POINT ─────────────────────────────────────────────────────────────
case "${1:-status}" in
  down)    down ;;
  up)      up ;;
  status)  status ;;
  restart) restart ;;
  *)
    echo "Usage: ./cluster.sh [down|up|status|restart]"
    echo ""
    echo "  down     scale everything to 0 (cool down your Mac)"
    echo "  up       restore everything back to running"
    echo "  status   see what's running right now"
    echo "  restart  down then up"
    exit 1
    ;;
esac