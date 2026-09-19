# azure_arc

Installs `azcmagent` and enrols the host in Azure Arc with a service principal, so the machine is visible to Azure Monitor and policy.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — dependencies, Microsoft repo, `azcmagent`, enrolment, verification.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `arc_tenant_id` | `b48c71d0-46cf-4171-ad02-1ed785ba425d` | Entra tenant. |
| `arc_subscription_id` | `a8a36bc1-79a7-49fe-9faa-92220103c66f` | Azure subscription. |
| `arc_location` | `polandcentral` | Arc resource location. |
| `arc_resource_group` | `homelab-rg` | Arc resource group. |
| `arc_spn_id` | `525b1595-071d-469f-a2c6-0680cda35b4b` | Service principal (app) ID. |
| `arc_spn_secret_name` | `arc-enrollment-secret` | Key Vault secret holding the SPN client secret. |
| `arc_keyvault_name` | `homelab-bysxdb-kv` | Key Vault. |
| `arc_machine_name` | `cloudlab` | Arc resource name; overridden in `host_vars/lab.yml`. |

## Notes

- The SPN client secret is read from Key Vault at run time (`no_log`); the controller needs `AZURE_*` credentials.
- Idempotent: `azcmagent connect` is only marked changed when it does not report `Already connected`.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
