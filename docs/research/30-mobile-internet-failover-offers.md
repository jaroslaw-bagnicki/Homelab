# 30 — Mobile Internet (5G/LTE data SIM) for Router Failover — PL offers

**Source**: Web research, Aug 24 2026 — operator sites (fonia.app, a2mobile.pl) +
[Antyweb — Internet na kartę roundup](https://antyweb.pl/internet-5g-na-karte-2026) (Jan 2026) +
[RankingOperatorzy — Internet na kartę bez umowy](https://rankingoperatorzy.pl/operatorzy/internet_na_karte_bez_umowy/) (Aug 2026)

**Scope**: Choosing a mobile-data plan for the homelab's **LTE/5G backup WAN** ([idea 08 —
Homelab LTE/5G WAN Failover](../ideas/08-lte-wan-failover.md), which hosts the OPNsense
multi-WAN failover).

**Status**: 📝 Analysis — **Flex SIM path FAQ-verified (2026-08-24)**. The additional Orange
Flex SIM is free, works in a router (configured as internet-only), and supersedes the paid
offers below. This doc stays as the alternatives / cost reference if the Flex SIM is ever
unsuitable (data pool, coverage).

> ✅ **FAQ-verified (2026-08-24)**: additional Flex SIM is free; usable in a **router** —
> Orange Flex recommends enabling **internet-only** services on it for router/iPad use; it
> does **not** work in roaming; PESEL must not be reserved (zastrzeżony) to order.
> ⚠️ **Still to check**: shared data-pool behaviour on exhaustion (throttle vs stop) and
> Orange 5G/LTE coverage at the S930's location; paid-plan prices rotate monthly.

---

## Context

The homelab edge plans a **Multi-WAN failover** ([idea 08](../ideas/08-lte-wan-failover.md)):
primary fiber WAN on the router's Broadcom card, backup WAN on the S930's onboard Realtek
port (`re0`) fed by the **reused ZTE WF830 LTE modem**.
The backup SIM needs: low recurring cost, ~30 GB/month comfort, no long-term contract, and
router compatibility. 31 GB is the user's sufficiency threshold.

## The chosen path — Orange Flex additional SIM (Aug 2026)

The user holds an **Orange Flex** subscription and can order an **additional SIM card at no
extra cost** (verified in the official [FAQ](https://flex.orange.pl/pomoc?category=dodatkowa-karta-sim)).
That SIM goes in the LTE modem as the backup WAN — the cheapest failover data option
(0 zł/month), sharing the Flex plan's data pool.

**FAQ-verified facts (2026-08-24):**

- **Free** — all additional SIMs/eSIMs are free. Count depends on the plan: 1 by default,
  2 on the 50 zł plan, 3 on the 80 zł plan.
- **Router use confirmed** — the FAQ explicitly recommends enabling **internet-only**
  services on the additional SIM when using it in a **router or iPad**. Order it with the
  "tylko internet" (internet-only) purpose.
- **Same number, same plan** — the additional SIM shares the main line's number and the
  plan's services/data.
- **No roaming** — the additional SIM does not work abroad; the main SIM does. Fine for a
  router that stays in Poland.
- **Ordering** — in the Flex app: *Mój numer → Dodaj SIM lub eSIM* (eSIM instantly;
  physical SIM via InPost Paczkomat or salon, ~3 business days). The **PESEL must not be
  reserved** (zastrzeżony) to order or swap the card.

**Still to verify before relying on it:** shared data-pool behaviour when the pool is
exhausted (speed throttle vs stop), and Orange 5G/LTE coverage at the S930's location.

If the Flex SIM is unsuitable, the paid offers below remain the fallback.

### Cheapest failover-only strategies (0–15 zł, from the LTE-modem thread)

For a link that mostly sits in standby (gateway pings, tunnels, notifications), the
cheapest strategies from the "Homelab LTE failover" thread:

| Strategy | Cost | How it works |
|---|---|---|
| **Virgin Mobile / Play na kartę** | ~0–5 zł/mo | Starter + 5 zł top-up + "Rok Ważności Konta" promo; activate a one-off GB pack (app/SMS) only when fiber is down |
| **Orange na kartę + KWR** | ~15 zł/year | "Konto Ważne Rok" keeps the line alive almost free; dense 5G coverage, low ping; top up for a GB pack only during an outage |
| **Plush / Play na kartę** (autotop-up) | 10–15 zł/mo | Recurring 10–15 zł top-ups earn bonus GB packs (often 10–30 GB) that roll over while top-ups continue |

**CGNAT**: most mobile operators CGNAT the backup WAN — fine when inbound traffic flows
over Cloudflare Tunnel / Tailscale; a direct WireGuard/IPsec endpoint over the backup link
needs a (sometimes paid) public-IP add-on.

**No-contract rule**: any plan requiring a signed contract (**abonament** — even an
indefinite-term one with a 1-month notice) is **rejected**; only **prepaid (na kartę)** or
**cancel-anytime** plans qualify. This rejects e.g. **OTVARTA** "O! Szybki" (13,99 zł/10 GB
— indefinite-term abonament on Plus) plus other subscription offers (nju, lajt mobile,
Virgin abonament, Plush abonament).

## Requirements for a paid failover SIM (fallback)

| Criterion | Target |
|---|---|
| Monthly cost | as low as possible; user baseline 17 zł/mo |
| Data volume | ~30 GB (user: 31 GB sufficient); more is fine |
| Contract | none — prepaid (na kartę) or cancel-anytime only; abonament (contract) rejected, even indefinite-term |
| Router use | SIM must work in a 5G modem/router (data-only SIM or allowed tethering) |
| Tech | LTE (ZTE WF830) primary; 5G optional |
| Network | pick on home coverage: Orange, Plus, Play, or T-Mobile |

## Fonia — the cheapest ≥30 GB baseline (Aug 2026)

**Fonia SIM** (subscription with calls, no contract) — Orange **or** Plus network (choose at
order), 5G, eSIM or physical SIM, 1 zł activation per number, monthly/quarterly/annual
billing:

| Plan | 1st month (−50% promo) | From 2nd month | Extras |
|---|---|---|---|
| **31 GB** | 8,50 zł | **17 zł** | unlimited calls/SMS/MMS, EU roaming 5,81 GB |
| 50 GB | 12,50 zł | 25 zł | EU roaming 10 GB |
| 100 GB | 16,50 zł | 33 zł | EU roaming 15,49 GB |

**Fonia Internet** (dedicated data-only SIM for home/cameras — the router-fit line):

| Plan | Price | Use case |
|---|---|---|
| 10 GB | 10 zł/mo | "idealny do kamer" |
| 200 GB | 40 zł/mo | "idealny do domu" |
| 500 GB | 69 zł/mo | "idealny do domu" |

**Takeaway**: the **31 GB / 17 zł** SIM was the cheapest *absolute* monthly cost for ≥30 GB
found — before the Orange Flex additional SIM (0 zł) superseded it.

## Alternative offers (PL market, Aug 2026)

### MVNOs — data-first / router-friendly

| Provider (network) | Offer | Price/mo | Data | Notes |
|---|---|---|---|---|
| **a2mobile** (Plus) | Niewyczerpalne Wszystko | 19,90 zł | 20 GB (up to 55 GB w/ tenure) | 31 days, code `*222*1#`; data-first MVNO, router-friendly |
| a2mobile (Plus) | Niewyczerpalne Wszystko | 24,90 zł | up to 55 GB | code `*249*1#` |
| a2mobile (Plus) | Niewyczerpalne Wszystko | 29,90 zł | up to 95 GB | Bestseller; code `*299*1#` |
| a2mobile (Plus) | Niewyczerpalne Wszystko | 34,90 / 39,90 / 49,90 zł | up to 140 / 190 / 400 GB | 5G, unlimited calls/SMS/MMS; 999 GB promo extras |
| a2mobile (Plus) | Internet na kartę (data-only) | 12,90 zł | 5 GB (throttle 3→1→0,5 Mb/s) | data-only; per Antyweb Jan 2026 |
| **aero2** (Plus) | data-only packs | 30 zł | 50 GB | aero2 = Plus data brand for routers; pack extends account 12 mo (free 512 kb/s BDI discontinued 2024) |
| aero2 (Plus) | data-only | 50 zł | 150 GB | |
| **Lycamobile** (Plus) | internet pack | 25 zł | 30 GB | |
| Lycamobile (Plus) | internet pack | 35 zł | 50 GB | |
| **Klucz Mobile** (Plus) | internet | 39,90 zł | 80 GB | |
| Klucz Mobile (Plus) | internet | 50 zł | 100 GB (+200 GB at night) | |
| **Mobile Vikings** (Play) | Burza | 60 zł | 260 GB 5G | overkill for failover |

### Big operators — prepaid data

| Provider | Offer | Price | Data | Notes |
|---|---|---|---|---|
| **Orange Flex** | additional SIM | **0 zł** (on existing sub) | shares plan data pool | Orange network; the chosen path |
| **Orange** | internet na kartę | 5 / 15 / 30 zł | 1 / 5 / 30 GB per month | dedicated data SIM |
| **Play** | internet na kartę | 50 zł/mo | 200 GB | via Play24 app; code activation = half |
| Play | internet na kartę | 20 zł/week | 30 GB | |
| Play | Fakt Mobile | 3–15 zł | 1–10 GB | |
| **T-Mobile** | GO! packs (prepaid) | 35–50 zł/mo | 5G + unlimited calls/SMS | prepaid (na kartę), no contract — richer but pricier |
| T-Mobile | starter online promo | 20 zł one-off | 12×833,25 GB over a year | |
| **tuBiedronka** (T-Mobile) | | 5 / 10 zł | 1 / 3 GB | |

## Cost-per-GB comparison (≈30 GB sweet spot)

| Offer | Price/mo | Data | zł/GB |
|---|---|---|---|
| **Orange Flex additional SIM** | **0 zł** (on existing sub) | shared pool | **0** |
| Fonia 31 GB | 17 zł | 31 GB | 0,55 |
| a2mobile 19,90 | 19,90 zł | 20 GB (55 w/ tenure) | ~1,00 (0,36 w/ tenure) |
| a2mobile 29,90 | 29,90 zł | up to 95 GB | ~0,31 |
| Lycamobile 30 GB | 25 zł | 30 GB | 0,83 |
| aero2 50 GB | 30 zł | 50 GB | 0,60 |
| Orange 30 GB | 30 zł | 30 GB | 1,00 |
| Klucz 80 GB | 39,90 zł | 80 GB | 0,50 |

## Recommendation

- **Primary: Orange Flex additional SIM (0 zł/mo)** in the LTE modem — verify modem/router
  use and data-pool behaviour before relying on it.
- **Fallback if Flex isn't suitable** (no-contract only): Fonia 31 GB / 17 zł for the
  cheapest ≥30 GB headroom (cancel anytime); a2mobile (best zł/GB, Plus network) if a lot
  of data is wanted. Near-zero-cost idling via Virgin/Play or Orange na kartę +
  account-validity promos (top up for a GB pack only during an outage).
- **Router-native fallbacks**: aero2 (data-only by design) or Play/Orange
  internet-na-kartę data SIMs if router compatibility is a hard requirement.
- **Coverage first**: verify the chosen network's coverage at the S930's location — signal
  decides whether the failover link is usable at all.

## Open questions

1. How does the additional Flex SIM draw from the shared data pool on exhaustion (speed
   throttle vs stop)?
2. Which network has better signal at home? (Orange Flex is Orange-only; paid fallbacks
   offer Orange/Plus/Play/T-Mobile choice.)
3. Is 31 GB/month a realistic cap, or should the fallback plan scale up (50/100 GB) during
   extended outages?

## Sources

- Orange Flex — [pomoc: dodatkowa karta SIM](https://flex.orange.pl/pomoc?category=dodatkowa-karta-sim)
- Fonia — [SIM subscription](https://fonia.app/zamow-sim/) · [Internet (data-only)](https://fonia.app/zamow-fonia-internet/) · [regulamin](https://fonia.app/regulamin-ofert-promocyjnych-fonia-sim-e-sim-oraz-data-wazny-od-11-06-2026/)
- a2mobile — [pakiety](https://www.a2mobile.pl/pakiety) · [5G](https://www.a2mobile.pl/5g)
- Antyweb — [Internet na kartę — wszystkie oferty (Jan 2026)](https://antyweb.pl/internet-5g-na-karte-2026)
- RankingOperatorzy — [Internet na kartę bez umowy (Aug 2026)](https://rankingoperatorzy.pl/operatorzy/internet_na_karte_bez_umowy/)
- Idea context — [idea 08 — Homelab LTE/5G WAN Failover](../ideas/08-lte-wan-failover.md) · [idea 07 — OPNsense router](../ideas/07-opnsense-futro-s930.md)
