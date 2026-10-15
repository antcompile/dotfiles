# prod-logs — live-tail logs from a service's pods on the production cluster.
#
# Usage:
#   prod-logs lakshmi                    # tail the lakshmi svc pods (follow)
#   prod-logs lakshmi-background         # tail the background worker pods
#   prod-logs lakshmi -g low_balance     # only lines matching a regex (needs rg)
#   prod-logs lakshmi -s 30m -t 500      # more history before following
#   prod-logs savings-plans -n savings   # override the namespace
#   prod-logs lakshmi -p                  # list pods in the ns instead of tailing
#
# Needs: kubectl + the prod kube-context below.

const PROD_CONTEXT = "gke_bitstack_europe-west1_bitstack-1"

def prod-logs [
    service: string                 # deployment name / label value (e.g. lakshmi, lakshmi-background)
    --namespace (-n): string        # k8s namespace (default: first '-' segment of service)
    --since (-s): string = "5m"     # how far back to start (kubectl duration, e.g. 30m, 2h)
    --tail (-t): int = 200          # lines of history per pod before following
    --grep (-g): string             # only show lines matching this regex (needs rg)
    --pods (-p)                     # list pods in the namespace instead of tailing logs
    --context (-c): string = $PROD_CONTEXT
] {
    let ns = ($namespace | default ($service | split row "-" | first))

    if $pods {
        ^kubectl --context $context -n $ns get pods -o wide
        return
    }

    let sel = $"services.bitstack-app.com/name=($service)"

    let probe = (do -i { kubectl --context $context -n $ns get pods -l $sel -o name } | complete)
    if $probe.exit_code != 0 {
        print $"prod-logs: kubectl failed \(context ($context), ns ($ns)\):"
        print ($probe.stderr | str trim)
        return
    }
    let names = ($probe.stdout | lines | where { |l| ($l | str trim | str length) > 0 })
    if ($names | is-empty) {
        print $"prod-logs: no pods with label ($sel) in namespace ($ns)."
        print $"          list what's there with:  prod-logs ($service) -p"
        return
    }
    print $"prod-logs: following ($names | length) pod\(s\) — ns=($ns), since=($since)"

    if ($grep | is-empty) {
        (^kubectl --context $context -n $ns logs -f -l $sel
            --prefix --max-log-requests 30 --since $since --tail $tail)
    } else {
        (^kubectl --context $context -n $ns logs -f -l $sel
            --prefix --max-log-requests 30 --since $since --tail $tail)
        | ^rg --line-buffered --color always $grep
    }
}
