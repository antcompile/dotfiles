# fix-ci-runners — repair staging CI runners poisoned with a stale static
# Artifact Registry docker token (see scripts/fix-poisoned-ci-runners.sh).
#
# SSHes into every RUNNING instance in the staging CI runner MIG via
# `gcloud compute ssh --tunnel-through-iap`, strips the static AR auth entry
# from the github-runner's docker config, and reverts it to clean ADC auth.
#
# Usage:
#   fix-ci-runners              # scan + fix
#   fix-ci-runners --dry-run    # scan + report only, change nothing

def fix-ci-runners [--dry-run (-d)] {
    let script = ("~/.config/nushell/scripts/fix-poisoned-ci-runners.sh" | path expand)
    if not ($script | path exists) {
        print $"fix-ci-runners: script not found at ($script)"
        return
    }
    if $dry_run {
        ^bash $script --dry-run
    } else {
        ^bash $script
    }
}
