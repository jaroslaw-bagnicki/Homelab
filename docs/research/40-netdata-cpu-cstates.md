# 40 — Visualizing CPU C-states in Netdata

**Source**: operator request, 2026-10-17 — "visualize CPU C-states in Netdata". No external thread.

**Scope**: the Netdata agent fleet (`pve` parent, `lab` / `nas` / `edge` children) — how C-state
residency is collected, why it is missing from the dashboards today, and the single setting that turns
it on. Not a power-monitoring design: it is a per-node diagnostic signal beside the existing CPU
charts ([ADR 27](../decisions/27-monitoring-strategy.md), [runbook 31](../runbooks/31-deploy-netdata.md)).

**Status**: 📋 Researched — ready to implement as a role change.

> **Verification**: mechanics read from the **v2.12.1** source (`src/collectors/proc.plugin/proc_stat.c`,
> the version running on every node) and the upstream integration metadata; fleet facts captured live
> over SSH on 2026-10-17. The dashboard placement after enabling is the only part not yet exercised.

---

## §1 — What a C-state is, briefly

A C-state is a processor **idle** power state. C0 is *executing*; C1/C1E halt the core clock; C3 and
the deeper C6/C7/C8/C9/C10 states progressively power-gate parts of the core and package. Deeper states
save more power but add wake latency, so a governor/driver decides how deep an idle core goes.

Linux exposes the residency counters through `cpuidle` sysfs — per core and per state:

```
/sys/devices/system/cpu/cpu0/cpuidle/state0/{name,time,latency,residency,usage,disable}
/sys/devices/system/cpu/cpuidle/current_driver          # e.g. intel_idle
```

`name` is the state label (`POLL`, `C1`, `C1E`, `C3`, `C6`, `C7s`, `C8`, `C9`, `C10`, `C6N`, `C6S` — the
set is per CPU family), and `time` is the **cumulative microseconds** spent in that state since boot.

## §2 — How Netdata collects it

The Netdata collector is the **`proc.plugin` `/proc/stat` module** — not `apps.plugin`, not a go.d job.
It combines two sources in one chart per core:

| Dimension | Source | Notes |
|---|---|---|
| `active` (displayed "C0 (active)") | `/proc/schedstat`, per-core line, field 7 | CPU run time in ns, divided by 1000 → µs |
| one dimension per state | `cpuidle/stateN/name` + `cpuidle/stateN/time` | cumulative µs, lowercased into the dimension id |

The chart is a **stacked percentage** — `PCENT_OVER_DIFF_TOTAL` normalises the deltas across all
dimensions, so every core always sums to ~100 % of its time. Chart identity (v2.12.1 source):

- type `cpu`, id `cpu<N>_cpuidle`, family `cpuidle`, context **`cpuidle.cpu_cstate_residency_time`**
- title **"C-state residency time"**, unit `percentage`
- one chart **per core**, labelled with `cpu: cpu<N>`

## §3 — Why the charts are missing today

The option lives in `[plugin:proc:/proc/stat]` in `netdata.conf` and is **off by default**:

```text
[plugin:proc:/proc/stat]
    cpu idle states = yes
```

Three findings from the installed **v2.12.1** source (`proc_stat.c`):

1. `do_cpuidle` initialises to `CONFIG_BOOLEAN_NO` for systems with **≤ 128 CPUs** (and is forced `no`
   above that threshold). The upstream README still says "more than 50 processors" — stale; the source
   and `metadata.yaml` agree on 128. Every fleet node is 2–4 cores, so the default is simply `no`.
2. **`auto` does not create the charts.** The chart-creation guard is
   `r != -1 && (do_cpuidle == CONFIG_BOOLEAN_YES || r > 0)`, while `read_cpuidle_states()` returns `0`
   on success and `1` only on error — so the `auto` value never satisfies it. `yes` is the only value
   that yields charts. (An `auto` written into `netdata.conf` looks configured but stays dark.)
3. `/proc/schedstat` must exist and parse; if the `stat()` on it fails the module forces the option back
   to `no` **regardless of the config value**.

`keep cpuidle files open` (default `yes` up to 24 CPUs) needs no change here.

**Live confirmation (2026-10-17)**: none of the four nodes carries a `[plugin:proc:/proc/stat]` section
in `/etc/netdata/netdata.conf`, so the defaults apply — and the parent's chart inventory
`/host/pve/api/v1/charts` (4.3 MB, all mirrored hosts) contains **zero** `cpuidle` charts.

## §4 — Fleet readiness (live-verified)

All four LAN nodes run Netdata **v2.12.1** and expose C-states through `intel_idle`; `/proc/schedstat`
is readable everywhere:

| Node | CPU | Cores | cpuidle driver | States on `cpu0` |
|---|---|---|---|---|
| `pve` | Celeron J4105 | 4 | `intel_idle` | POLL, C1, C1E, **C6 (time = 0)**, C7s, C8, C9, C10 |
| `lab` | Core i5-7500T | 4 | `intel_idle` | POLL, C1, C1E, C3, C6, C7s, C8 |
| `nas` | Pentium G4400 | 2 | `intel_idle` | POLL, C1, C1E, C3, C6, C7s, C8 |
| `edge` | Atom x5-Z8350 | 4 | `intel_idle` | POLL, C1, C6N, C6S, C7, C7S |

`pve` advertises a `C6` state that has never been entered (`time = 0`) — state lists are data, not a
promise of use. `cloudlab` (VPS) runs the base playbook only and is not a Netdata host.

## §5 — Enabling it (recommended change)

One `ini_file` task in the shared `netdata` role, driven by a variable, on **all four** hosts — the
capability was verified on each, and the charts are cheap (one per core):

```yaml
# defaults/main.yml
netdata_cpu_idle_states: true
```

```yaml
# tasks/main.yml — beside the other netdata.conf options
- name: Configure CPU idle-state (C-state) charts
  community.general.ini_file:
    path: /etc/netdata/netdata.conf
    section: plugin:proc:/proc/stat
    option: cpu idle states
    value: "{{ 'yes' if netdata_cpu_idle_states | bool else 'no' }}"
    mode: "0644"
  notify: Restart netdata
```

Writing the value in both directions keeps the task idempotent and makes "off" explicit rather than
implied by absence.

Manual test on one node before the role change:

```bash
cd /etc/netdata && sudo ./edit-config netdata.conf     # add the two lines above
sudo systemctl restart netdata
curl -sk https://192.168.2.201:19999/host/<host>/api/v1/charts | grep -o 'cpu[0-9]*_cpuidle' | sort -u
```

Follow-ups for the implementing PR: a note in [runbook 31](../runbooks/31-deploy-netdata.md)'s config
section, and the `CHANGELOG.md` entry; the Observability table in [overview](../overview.md) needs no
new row — this extends the existing "Node metrics" signal.

## §6 — What appears

One chart **per core**, per host — 14 charts fleet-wide (4 + 4 + 2 + 4), all under the `cpuidle` family
and named "C-state residency time". Each shows `active` plus one dimension per kernel state, stacked to
~100 %. On the new dashboard they surface beside the other CPU charts; searching the Metrics tab for
"C-state" is the reliable way to find a specific core.

## §7 — Caveats

- **Per-core, never aggregated.** Netdata does not merge cores into a fleet chart; use the family view
  or filter by host.
- **The collector wakes idle cores.** When a core showed no run time in an interval, `proc.plugin`
  briefly schedules a thread pinned to that core so the cpuidle counters advance. That is one short
  wake per fully idle core per collection interval — deliberate, negligible, but it does mean the act of
  monitoring touches the states being measured.
- **Host-level only.** `cpuidle` is not visible inside VMs or LXCs; the `pve` charts describe the
  physical Wyse 5070, not its guests.
- **Residency is not utilisation.** A busy core lives in C0/C1 and `POLL` is its own dimension — read
  `active` (or the existing `cpu.cpu` utilisation chart) for load, and the deep states for idleness.
- **Storage**: 14 extra charts is noise for the parent's tiers; `edge` is RAM-backed, so its history is
  the shortest regardless.

## §8 — Reading the charts

- Deep-state (C6+) residency high on an otherwise idle host = expected and power-saving.
- A core pinned in C0/C1 with low application CPU points at interrupts, polling or a busy kernel
  thread — cross-check `cpu.interrupts`, `cpu.softirqs` and the per-core utilisation chart.
- Compare cores: one hot core among idle siblings usually means a pinned service or IRQ affinity.
- For power tuning, watch the fleet's deep-state mix after a change (a governor, a BIOS C-state
  setting, a new always-on guest) — the effect is visible here first.

## §9 — Verification checklist

| Check | Command | Expected |
|---|---|---|
| States exposed | `cat /sys/devices/system/cpu/cpuidle/current_driver` | `intel_idle` |
| Active-time source | `test -r /proc/schedstat && echo ok` | `ok` |
| Option present | `grep -A2 'plugin:proc:/proc/stat' /etc/netdata/netdata.conf` | `cpu idle states = yes` |
| Charts created | `curl -sk https://<parent>:19999/host/<host>/api/v1/charts \| grep -c cpuidle` | one per core (4/4/2/4) |
| Sanity fallback | `cpupower idle-info` | same state names |

## References

- Netdata `proc.plugin` — [README (CPU idle states)](https://github.com/netdata/netdata/blob/master/src/collectors/proc.plugin/README.md#cpu-idle-states) · [integration metadata](https://github.com/netdata/netdata/blob/master/src/collectors/proc.plugin/metadata.yaml) (`cpuidle.cpu_cstate_residency_time`)
- Netdata v2.12.1 source — [`proc_stat.c`](https://github.com/netdata/netdata/blob/v2.12.1/src/collectors/proc.plugin/proc_stat.c) (option defaults, chart creation, wake logic)
- Linux kernel — [`cpuidle` sysfs ABI](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-devices-system-cpu)
- [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [runbook 31 — deploy Netdata](../runbooks/31-deploy-netdata.md) · [hardware](../hardware.md)
