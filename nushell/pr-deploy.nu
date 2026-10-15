# pr-deploy — deploy the current `core` branch to staging without
# remembering the branch name or the argocd app names.
#
# Infers:
#   • target revision = current git branch (or `develop` with --revert)
#   • argocd apps      = mapped from the branch's diff vs origin/develop,
#                        then validated against the live argocd app list
#   • shared-lib changes (libs/integrations/protos/common) don't map to a
#     service directly, so their consumer binaries are resolved via
#     `bazel query rdeps(...)` and those services are deployed too.
# then calls tools/staging-deploy/staging-deploy.sh.
#
# Usage:
#   pr-deploy            # deploy current branch to staging
#   pr-deploy --revert   # roll the same apps back to develop
#   pr-deploy --yes      # skip the confirmation prompt

const ARGOCD_SERVER = "argocd-staging.eland-goldeye.ts.net"

# Map one changed path to a candidate argocd app name (or null to skip).
# Mirrors the staging-deploy skill's mapping table.
def pr-deploy-candidate [path: string] {
    let parts = ($path | split row "/")
    if ($parts | length) == 1 { return null }   # repo-root file (README, MODULE.bazel…)

    let top = ($parts | first)
    if ($top | str starts-with ".") { return null }   # .claude, .github, .devcontainer…
    let skip = [protos libs tools docs ci infra common scratches third_party svc integrations etl]
    if $top in $skip { return null }

    # Legacy Go renames take precedence over the generic rules.
    let legacy = {ambergo: amber, bitstack_api: bitstack-api, anubisgo: anubis, patrongo: patron}
    if $top in ($legacy | columns) { return ($legacy | get $top) }

    if ($parts | length) >= 3 {
        let sub = ($parts | get 1)
        let kind = ($parts | get 2)
        if $kind in [svc wrk] {
            let suffix = (if $kind == "wrk" { "-wrk" } else { "" })
            return $"($top)-($sub)($suffix)"
        }
        return $"($top)-($sub)"
    }

    # <top>/<anything> → <top>
    return $top
}

# Shared code dirs whose changes have no service of their own — their
# consumers are resolved via bazel rdeps instead of being skipped.
const SHARED_DIRS = [libs integrations protos common]

# Map a bazel binary target (//top/sub/...:name) to a candidate argocd app
# by reusing the path-based mapping above. Appends a fake leaf so a target
# like //anubisgo/cmd/svc:svc is treated as the path anubisgo/cmd/svc/_.
def pr-deploy-target-candidate [target: string] {
    let path = ($target | str replace --regex '^//' '' | split row ":" | first)
    pr-deploy-candidate $"($path)/_"
}

# GitButler stores its integration state on `gitbutler/workspace`; the real
# feature branches are pushed to `origin/<name>`. Infer the current one as the
# remote branch (that isn't an integration/main branch) nearest to HEAD.
def pr-deploy-infer-branch [] {
    let skip = ["origin/HEAD" "origin/develop" "origin/main" "origin/master" "origin/gitbutler/workspace" "origin/gitbutler/target"]
    let ranked = (
        git for-each-ref --format '%(refname:short)' refs/remotes/origin
        | lines
        | where { |b| ($b | str trim) not-in $skip }
        | each { |b|
            let anc = (do -i { git merge-base --is-ancestor $b HEAD } | complete)
            if $anc.exit_code == 0 {
                {branch: ($b | str replace "origin/" ""), dist: (git rev-list --count $"($b)..HEAD" | into int)}
            } else { null }
        }
        | where { |x| $x != null }
        | sort-by dist
    )
    if ($ranked | is-empty) { null } else { ($ranked | first | get branch) }
}

def pr-deploy [--revert (-r), --yes (-y)] {
    let root = (do -i { git rev-parse --show-toplevel } | str trim)
    let script = $"($root)/tools/staging-deploy/staging-deploy.sh"
    if ($root | is-empty) or (not ($script | path exists)) {
        print $"pr-deploy: not inside the core repo \(missing ($script)\)"
        return
    }

    let cur = (git branch --show-current | str trim)
    # GitButler workspace (or detached HEAD): infer the pushed feature branch.
    let use_remote = ($cur | str starts-with "gitbutler/") or ($cur | is-empty)
    let branch = if $use_remote {
        let inferred = (pr-deploy-infer-branch)
        if ($inferred | is-empty) {
            print "pr-deploy: gitbutler workspace but no pushed feature branch found under origin/. Push your virtual branch first."
            return
        }
        print $"pr-deploy: gitbutler workspace — inferred branch '($inferred)'"
        $inferred
    } else { $cur }

    if (not $revert) and ($branch == "develop") {
        print "pr-deploy: on develop — nothing to deploy. Use --revert to roll staging back."
        return
    }
    let rev = if $revert { "develop" } else { $branch }

    # --- detect changed paths vs origin/develop ---
    do -i { git fetch origin develop } | complete | ignore
    do -i { git fetch origin $branch } | complete | ignore
    # For an inferred/pushed branch, diff its remote ref so we only see THAT
    # branch's changes — not the whole gitbutler workspace's applied set.
    let diff_base = if $use_remote { $"origin/($branch)" } else { "HEAD" }
    let files = (
        git diff --name-only $"origin/develop...($diff_base)"
        | lines
        | where { |f| ($f | str trim | str length) > 0 }
    )
    if ($files | is-empty) {
        print "pr-deploy: no diff vs origin/develop — nothing to deploy."
        return
    }

    # --- pull the live argocd app list for validation ---
    let list = (do { ^argocd --grpc-web --server $ARGOCD_SERVER app list -o name } | complete)
    if $list.exit_code != 0 {
        print "pr-deploy: can't reach argocd. Tailscale up? Logged in? Try:"
        print $"  argocd --grpc-web --server ($ARGOCD_SERVER) login --sso ($ARGOCD_SERVER)"
        print ($list.stderr | str trim)
        return
    }
    let apps_all = ($list.stdout | lines | each { |l| $l | str replace "argocd/" "" | str trim })

    # --- resolve candidates → real apps (+ worker siblings) ---
    # Directly-mapped services (a changed path that IS a service).
    let direct_candidates = (
        $files
        | each { |f| pr-deploy-candidate $f }
        | where { |c| $c != null }
        | uniq
    )

    # Shared-lib changes: no service of their own, so resolve consumer
    # binaries from the build graph and deploy those instead.
    let shared_files = (
        $files
        | where { |f|
            let parts = ($f | split row "/")
            (($parts | length) > 1) and (($parts | first) in $SHARED_DIRS)
        }
    )
    let consumer_candidates = if ($shared_files | is-empty) { [] } else {
        let pkgs = ($shared_files | each { |f| $"//($f | path dirname):all" } | uniq)
        print $"pr-deploy: shared-lib change — resolving consumers of ($pkgs | length) package\(s\) via bazel rdeps \(this can take a bit\)…"
        let q = ('kind("go_binary", rdeps(//..., set(' + ($pkgs | str join " ") + ')))')
        let res = (do { ^bazel query $q } | complete)
        if $res.exit_code != 0 {
            print "pr-deploy: bazel rdeps query failed — can't resolve shared-lib consumers:"
            print ($res.stderr | lines | last 5 | str join "\n")
            []
        } else {
            $res.stdout
            | lines
            | where { |l| $l | str starts-with "//" }
            | each { |t| pr-deploy-target-candidate $t }
            | where { |c| $c != null }
            | uniq
        }
    }

    let candidates = ($direct_candidates | append $consumer_candidates | uniq)

    mut resolved = []
    for c in $candidates {
        let app = if $c in $apps_all {
            $c
        } else {
            # fall back to the bare top-level domain (e.g. insights-provider → insights)
            let base = ($c | split row "-" | first)
            if $base in $apps_all { $base } else { null }
        }
        if $app == null {
            print $"pr-deploy: no argocd app for candidate '($c)' — skipping"
            continue
        }
        $resolved = ($resolved | append $app)
        # sibling worker apps (svc + wrk/bdg share source files)
        for suf in [wrk bdg] {
            let sib = $"($app)-($suf)"
            if $sib in $apps_all { $resolved = ($resolved | append $sib) }
        }
    }
    let resolved = ($resolved | uniq)
    if ($resolved | is-empty) {
        print "pr-deploy: no deployable services detected (branch only touches shared libs / tooling)."
        return
    }

    # --- confirm branch is on origin (deploy only; argocd syncs origin) ---
    # Skip for gitbutler-inferred branches — they're already remote by construction.
    if (not $revert) and (not $use_remote) {
        let on_origin = (do -i { git ls-remote --exit-code --heads origin $branch } | complete)
        if $on_origin.exit_code != 0 {
            print $"pr-deploy: branch '($branch)' is not on origin. Push first with:"
            print $"  git push -u origin ($branch)"
            return
        }
    }

    # --- show plan + confirm ---
    print $"Plan \(deploy ($rev)\):"
    $resolved | each { |a| print $"  • ($a)" }
    if not $yes {
        let reply = (input "Proceed? [y/N] ")
        if ($reply | str lowercase) != "y" { print "aborted"; return }
    }

    ^$script $rev ...$resolved
}
