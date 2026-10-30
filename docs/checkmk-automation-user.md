---
status: current
---

# Checkmk automation user

The Checkmk Terraform units in [`terragrunt/`](../terragrunt/README.md#checkmk-configuration) (`checkmk-password`, `checkmk-rustfs-monitoring`, `checkmk-longhorn-monitoring`) authenticate as the Checkmk automation user `terraform`, through the `checkmk` entry in `terragrunt/global-secrets.sops.yaml`. This doc sets up that user's permissions on the Checkmk site; see [ADR 0015](decisions/0015-checkmk-configuration-as-code.md) for why Checkmk is configured through Terraform, and [`reference/monitoring-sites.md`](reference/monitoring-sites.md) for the sites.

## The automation user's role

`terraform` does not need to be an administrator. Create a role from the built-in `no_permissions` role with exactly the 14 permissions the Checkmk modules need, and give it to the user. This was verified against a Checkmk Raw 2.4 site: with only this role the provider applied, re-planned without changes and destroyed everything the spike created. (A role cloned from `user` also works but carries about 370 inherited permissions, including 16 more Setup ones, so do not use it.) Use an existing Checkmk admin account for these calls and read its secret without echoing it:

```sh
CMK='https://<checkmk-host>/<site>/check_mk/api/1.0'   # no trailing slash
read -rs ADMIN_SECRET                                  # paste the admin user's secret, press Enter
AUTH="Authorization: Bearer <admin-username> $ADMIN_SECRET"

# 1. Create the role from no_permissions
curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$CMK/domain-types/user_role/collections/all" \
  -d '{"role_id":"no_permissions","new_role_id":"tf_auto","new_alias":"Terraform automation"}'

# 2. Grant exactly these 14 permissions
curl -sS -X PUT -H "$AUTH" -H 'Content-Type: application/json' \
  "$CMK/objects/user_role/tf_auto" \
  -d '{"new_permissions":{"general.use":"yes","wato.use":"yes","wato.edit":"yes","wato.passwords":"yes","wato.edit_all_passwords":"yes","wato.edit_hosts":"yes","wato.manage_hosts":"yes","wato.edit_folders":"yes","wato.manage_folders":"yes","wato.all_folders":"yes","wato.see_all_folders":"yes","wato.rulesets":"yes","wato.activate":"yes","wato.activateforeign":"yes"}}'

# 3. Give the existing `terraform` automation user that role (a PUT needs the object's ETag in If-Match)
ETAG=$(curl -sS -D - -o /dev/null -H "$AUTH" "$CMK/objects/user_config/terraform" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
curl -sS -X PUT -H "$AUTH" -H 'Content-Type: application/json' -H "If-Match: $ETAG" \
  "$CMK/objects/user_config/terraform" -d '{"roles":["tf_auto"]}'
```

Check with `GET $CMK/objects/user_role/tf_auto`: `extensions.permissions` must list exactly those 14. Step 1 fails if the role exists already; step 2 can be repeated. The same can be done in the UI (Setup > Users > Roles: clone **No permissions**, enable the same permissions, then set the user's role).
