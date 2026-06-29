# Incident: OPNsense DNS + NAT Outage — Cluster-Wide Connectivity Failure

**Date:** 2026-06-29  
**Duration:** ~3–4 hours  
**Severity:** Critical — all external image pulls failed, Cloudflare tunnel down, external DNS broken  
**Resolved by:** Manual OPNsense reconfiguration (WAN gateway + outbound NAT)

---

## Summary

A cluster-wide connectivity failure caused all pods requiring external network access to fail.
`cloudflared`, `external-dns`, `openclaw`, and `kubelet-serving-cert-approver` were all down.
Root causes were two silent misconfigurations in OPNsense:
1. Wrong WAN default gateway (`10.20.0.3` instead of `10.20.0.1`)
2. Outbound NAT auto-generation producing zero rules (silently broken)

---

## Symptoms

- `kubectl` commands timing out intermittently
- Pods stuck in `ImagePullBackOff` / `ErrImagePull` for images on `ghcr.io`, `registry.spinup.in`
- `cloudflared` pod crash-looping with: `lookup _v2-origintunneld._tcp.argotunnel.com ... i/o timeout`
- `external-dns` crash-looping
- No Mattermost alerts arriving
- `dig @192.168.60.1 ghcr.io` returning `SERVFAIL` from Proxmox host (`alif`)

---

## Investigation Path

### Step 1 — Talos nodes were blocking on time sync (separate prior incident)
Talos control plane (`192.168.60.40`) and worker (`192.168.60.41`) had been stuck at
epoch 0 due to DNS lookup failures for NTP servers. Fixed via:
```
talosctl -n 192.168.60.40 patch machineconfig --patch '{"machine":{"network":{"nameservers":["192.168.60.1"]},"time":{"disabled":true}}}'
talosctl -n 192.168.60.41 patch machineconfig --patch '{"machine":{"network":{"nameservers":["192.168.60.1"]},"time":{"disabled":true}}}'
```

### Step 2 — DNS returning SERVFAIL from OPNsense
After cluster recovered, all pods pulling from external registries failed with DNS errors.
Testing from `alif` (Proxmox, `10.20.0.10`):
```bash
dig @192.168.60.1 ghcr.io       # → SERVFAIL
dig @1.1.1.1 ghcr.io            # → 20.207.73.86 (working fine)
```
OPNsense's Unbound DNS was in **recursive resolution mode** with no upstream forwarders,
and recursive resolution was failing because OPNsense WAN had no internet connectivity.

**Fix applied:** Added query forwarding entries in OPNsense:
`Services > Unbound DNS > Query Forwarding` → added `1.1.1.1:53` and `1.0.0.1:53` (empty domain = catch-all)

### Step 3 — OPNsense WAN had wrong default gateway
Even after adding forwarders, Unbound still returned SERVFAIL.
Testing from OPNsense console:
```
drill ghcr.io @1.1.1.1   # → "error sending query: Could not send or receive, network error"
ping 1.1.1.1             # → 100% packet loss
ping 10.20.0.3           # → "Destination Net Unreachable" (gateway was responding but not routing)
ping 10.20.0.1           # → 0% packet loss (real internet gateway)
```

OPNsense routing table showed `default via 10.20.0.3` but `10.20.0.3` returned
`Destination Net Unreachable` for all external traffic.  
`alif` (Proxmox) uses `default via 10.20.0.1` and had full internet access.

**Fix applied:**
- Temporary (shell): `route delete default; route add default 10.20.0.1`
- Permanent (UI): `System > Gateways > Configuration` → edited `WAN_DHCP` → set IP Address to `10.20.0.1`

> **Why was the gateway wrong?** The WAN interface uses DHCP. The DHCP server on `10.20.0.0/24`
> was providing `10.20.0.3` as the router option, which is not the real internet gateway.
> OPNsense learned the wrong gateway from DHCP and used it. Setting the gateway IP manually
> in the gateway config overrides the DHCP-provided value permanently.

### Step 4 — Pods still could not reach internet (TCP 443 timeout)
After DNS was fixed, image pulls still failed with:
```
dial tcp 20.207.73.86:443: i/o timeout
```
DNS was resolving correctly (ghcr.io → 20.207.73.86) but TCP connections to the internet timed out.

Test from pod (busybox cached image):
```bash
kubectl run nettest -n kube-system --rm -i --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"imagePullPolicy":"IfNotPresent","securityContext":{"runAsNonRoot":false}}}' \
  -- sh -c "nc -zvw5 20.207.73.86 443"
# → Connection timed out
```

### Step 5 — OPNsense outbound NAT had zero rules
`Firewall > NAT > Outbound` was set to **"Automatic outbound NAT"** but the
automatic rules table was **completely empty**. OPNsense was not NATing any traffic
from `192.168.60.0/24`.

**Fix applied:**
1. Switched to `Manual outbound NAT`
2. Added rule:
   - Interface: `WAN`
   - Source: `192.168.60.0/24` (NOT "LAN address" which is just `192.168.60.1`)
   - Source Port: `*`
   - Destination: `*`
   - NAT Address: `Interface address` (masquerade)
3. Saved and Applied

> **Watch out:** The auto-created rule defaulted to Source `LAN address` which only covers
> `192.168.60.1` (OPNsense itself). This must be changed to `192.168.60.0/24` to cover all
> hosts on the LAN.

---

## Full Root Cause Chain

```
DHCP server on 10.20.0.0/24 providing wrong gateway (10.20.0.3)
  └─► OPNsense WAN default route: 10.20.0.3 (Destination Net Unreachable)
        └─► OPNsense cannot reach internet
              └─► Unbound DNS forwarding to 1.1.1.1 fails → SERVFAIL
                    └─► CoreDNS upstream queries fail → cluster DNS broken
                          └─► Image pulls fail (DNS + TCP) → all pods down
                          └─► cloudflared tunnel down
                          └─► external-dns down

+ Separately: Outbound NAT auto-generation silently broken (0 rules)
      └─► Even with correct routing, LAN traffic was not masqueraded
            └─► TCP connections from 192.168.60.0/24 to internet dropped
```

---

## Fixes Applied (in order)

| # | What | Where | How |
|---|---|---|---|
| 1 | Added DNS forwarders to Unbound | OPNsense UI > Services > Unbound DNS > Query Forwarding | Added `1.1.1.1:53` and `1.0.0.1:53` with empty domain |
| 2 | Fixed WAN default gateway | OPNsense UI > System > Gateways > Configuration | Changed `WAN_DHCP` IP from `10.20.0.3` → `10.20.0.1` |
| 3 | Restarted Unbound DNS | OPNsense UI > Services > Unbound DNS | Click restart (▶) after gateway was correct |
| 4 | Added outbound NAT rule | OPNsense UI > Firewall > NAT > Outbound | Switched to Manual, added `192.168.60.0/24 → WAN Interface address` |
| 5 | Restarted affected pods | kubectl | `kubectl delete pods -n <ns> --all` for kubelet-serving-cert-approver, openclaw |

---

## Verification

After all fixes, confirmed from Proxmox host (`alif`):
```bash
dig +short @192.168.60.1 ghcr.io              # → 20.207.73.86
dig +short @192.168.60.1 mattermost.jamilshaikh.in  # → 104.21.78.211
dig +short @192.168.60.1 _v2-origintunneld._tcp.argotunnel.com SRV  # → region1, region2
```

Pod network egress:
```bash
kubectl run nettest -n kube-system --rm -i --image=busybox:1.36 \
  -- sh -c "nc -zvw5 20.207.73.86 443"
# → 20.207.73.86 (20.207.73.86:443) open
```

All pods healthy:
```
cloudflared                    2/2 Running
external-dns                   1/1 Running
openclaw                       1/1 Running
kubelet-serving-cert-approver  1/1 Running
```

---

## Lessons Learned

- **DNS failures cascade silently** — Unbound recursive failure → CoreDNS SERVFAIL → image pulls fail with misleading "server misbehaving" errors, not "DNS broken"
- **OPNsense auto NAT can silently produce zero rules** — always verify the automatic rules table actually has entries after saving
- **"LAN address" ≠ "LAN net"** in OPNsense NAT rules — `LAN address` = only `192.168.60.1`, `LAN net` or `192.168.60.0/24` = all hosts
- **DHCP-provided gateway can be wrong** — OPNsense on DHCP WAN learned the wrong gateway; override it statically in Gateways config
- **Test OPNsense connectivity FROM the firewall first** — `drill ghcr.io @1.1.1.1` from the OPNsense shell immediately shows whether WAN egress works

## Quick DNS Triage Checklist (for next time)

```bash
# 1. From alif (prox), test OPNsense DNS directly
dig @192.168.60.1 ghcr.io +time=3

# 2. Test OPNsense WAN reachability from OPNsense console
ping -c3 1.1.1.1
drill ghcr.io @1.1.1.1

# 3. Check OPNsense default route
netstat -rn | head -5    # default gateway should be 10.20.0.1

# 4. Test pod egress
kubectl run nettest -n kube-system --rm -i --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"imagePullPolicy":"IfNotPresent","securityContext":{"runAsNonRoot":false}}}' \
  -- sh -c "nc -zvw5 1.1.1.1 53; nc -zvw5 20.207.73.86 443"

# 5. Check OPNsense NAT outbound (UI)
# Firewall > NAT > Outbound → verify automatic rules table is NOT empty
# or manual rule for 192.168.60.0/24 → WAN exists
```
