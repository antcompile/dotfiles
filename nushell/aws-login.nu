#!/usr/bin/env nu

# Usage (to persist env vars like AWS_PROFILE / AWS_REGION / CLAUDE_CODE_USE_BEDROCK
# in your CURRENT nushell session):
#
#   source /Users/anthony.trad/Git/perso/dotfiles/nushell/aws-login.nu
#   aws-login playground14
#
# Or as a module:
#   use /Users/anthony.trad/Git/perso/dotfiles/nushell/aws-login.nu *
#   aws-login playground14
#
# Running it directly via `nu aws-login.nu <key>` will still perform the login,
# but env vars will NOT leak back into the parent shell (subprocess limitation).

# `def --env` is required so env var assignments propagate to the caller's scope
# when this file is sourced or imported as a module.
export def --env aws-login [aws_account_name: string] {
  # Base Okta/AWS CLI settings
  $env.OKTA_AWSCLI_ORG_DOMAIN = "checkout.okta.com"
  $env.OKTA_AWSCLI_CACHE_ACCESS_TOKEN = "true"
  $env.OKTA_AWSCLI_SESSION_DURATION = "36000"
  $env.OKTA_AWSCLI_EXPIRY_AWS_VARIABLES = "true"
  $env.OKTA_AWSCLI_WRITE_AWS_CREDENTIALS = "true"
  $env.OKTA_AWSCLI_OPEN_BROWSER = "true"

  $env.OKTA_AWSCLI_OIDC_CLIENT_ID = "0oar3nsvk7VtIvsL3357"

  # Default group (standard accounts)
  $env.IDP_NAME = "okta"
  $env.OKTA_AWSCLI_AWS_ACCOUNT_FEDERATION_APP_ID = "0oa423kknpZCS07GJ357"

  # Regional STS so token is valid across regions
  $env.AWS_REGION = "eu-west-1"
  $env.AWS_STS_REGIONAL_ENDPOINTS = "regional"

  mut role_name = "cko_issuing_infrastructure"
  mut account_id = ""

  match $aws_account_name {
    "engineering-knowledgebase-qa" => {
      $account_id = "495219733291"
      $role_name = "breakglass"
      $env.IDP_NAME = "OktaIDP"
      $env.OKTA_AWSCLI_AWS_ACCOUNT_FEDERATION_APP_ID = "0oaricq7oliS1Yb8G357"
    }
    "hackathon-2025" => {
      $account_id = "000710251778"
      $role_name = "breakglass"
      $env.IDP_NAME = "OktaIDP"
      $env.OKTA_AWSCLI_AWS_ACCOUNT_FEDERATION_APP_ID = "0oaricq7oliS1Yb8G357"
    }
    "playground11" => {
      $account_id = "979933559541"
      $role_name = "cko_playground_engineer"
      $env.IDP_NAME = "OktaIDP"
      $env.OKTA_AWSCLI_AWS_ACCOUNT_FEDERATION_APP_ID = "0oaricq7oliS1Yb8G357"
    }
    "playground14" => {
      $account_id = "101852531977"
      $role_name = "cko_playground_engineer"
      $env.IDP_NAME = "OktaIDP"
      $env.OKTA_AWSCLI_AWS_ACCOUNT_FEDERATION_APP_ID = "0oaricq7oliS1Yb8G357"
    }
    "dev" => {
      $account_id = "851429951072"
      $role_name = "cko_issuing_infrastructure"
    }
    "load-test" => {
      $account_id = "054697295645"
      $role_name = "cko_issuing_engineer"
    }
    "mgmt" => {
      $account_id = "791259062566"
      $role_name = "cko_issuing_engineer"
    }
    "prod" => {
      $account_id = "851392519502"
      $role_name = "cko_issuing_engineer"
    }
    "prod-viewonly" => {
      $account_id = "851392519502"
      $role_name = "cko_issuing_viewonly"
    }
    "qa" => {
      $account_id = "711533748762"
      $role_name = "cko_issuing_infrastructure"
    }
    "sbox" => {
      $account_id = "686496747715"
      $role_name = "cko_issuing_engineer"
    }
    "sbox-viewonly" => {
      $account_id = "686496747715"
      $role_name = "cko_issuing_viewonly"
    }
    _ => {
      print $"Unknown account key: ($aws_account_name)"
      print "Supported keys:"
      print "  engineering-knowledgebase-qa, hackathon-2025, playground11,"
      print "  playground14, dev, load-test, mgmt, prod, prod-viewonly, qa, sbox, sbox-viewonly"
      return
    }
  }

  let profile = $"cko-($aws_account_name)"
  let role_arn = $"arn:aws:iam::($account_id):role/($role_name)"
  let idp_arn = $"arn:aws:iam::($account_id):saml-provider/($env.IDP_NAME)"

  print $"Selected account: ($aws_account_name)"
  print $"Role ARN: ($role_arn)"
  print $"IDP ARN:  ($idp_arn)"
  print $"Profile:  ($profile)"

  ^okta-aws-cli --aws-iam-role $role_arn --aws-iam-idp $idp_arn --profile $profile

  # Set active profile for current shell session after successful login
  $env.AWS_PROFILE = $profile
  print $"AWS_PROFILE set to ($profile)"

  # Claude Code Bedrock toggle: only enabled on playground14
  if $aws_account_name == "playground14" {
    $env.CLAUDE_CODE_USE_BEDROCK = "1"
  } else {
    $env.CLAUDE_CODE_USE_BEDROCK = "0"
  }
  print $"CLAUDE_CODE_USE_BEDROCK set to ($env.CLAUDE_CODE_USE_BEDROCK)"
}

# Entry point for `nu aws-login.nu <key>`. Env vars set here do NOT persist in
# the parent shell — use `source` or `use` (see header) for that.
def --env main [aws_account_name: string] {
  aws-login $aws_account_name
}
