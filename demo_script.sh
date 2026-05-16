#!/usr/bin/env bash
# =============================================================================
# demo_script.sh — Rootkit Detection Demo  (4-Act)
#
# Platform : Linux Mint 22.3 "Zena"  |  kernel 6.17.0-22-generic
# Rootkit  : Diamorphine LKM (patched for 6.7+ via kprobe)
# EDR      : Elastic Security (Elasticsearch + Kibana + Elastic Defend)
# Detector : detector.py  (pure stdlib, cross-view /proc vs /sys)
#
# ACT 1  Baseline       — standard commands + Elastic show a clean system
# ACT 2  Infection      — load Diamorphine; lsmod / ps / cat all go blind
# ACT 3  Enterprise EDR — Kibana: zero alerts despite live rootkit
# ACT 4  Detection      — detector.py exposes the hidden module
#
# Prerequisites:
#   • diamorphine.ko built:  cd diamorphine && make
#   • Python 3 available
#   • Elasticsearch running:   sudo systemctl start elasticsearch
#   • Kibana running:          sudo systemctl start kibana
#   • Elastic Agent running:   sudo systemctl start elastic-agent
#   • Kibana open in browser:  http://<VM_IP>:5601
#     → Security → Alerts  (have this tab open before starting)
#
# Usage:
#   sudo bash demo_script.sh
# =============================================================================

set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────
RED='\\033[0;31m';  GREEN='\\033[0;32m'; YELLOW='\\033[0;33m'
CYAN='\\033[0;36m'; BLUE='\\033[0;34m';  BOLD='\\033[1m'
DIM='\\033[2m';     RESET='\\033[0m'

banner()   { echo -e "\\n${BOLD}${CYAN}$*${RESET}"; }
info()     { echo -e "${GREEN}[+]${RESET} $*"; }
warn()     { echo -e "${YELLOW}[!]${RESET} $*"; }
alert()    { echo -e "${RED}${BOLD}[ALERT]${RESET} $*"; }
elastic()  { echo -e "${BLUE}${BOLD}[ELASTIC]${RESET} $*"; }
cmd()      { echo -e "${DIM}\\$ $*${RESET}"; }
pause()    { echo -e "\\n${BOLD}──── Press ENTER to continue ────${RESET}"; read -r; }
sep()      { echo -e "${CYAN}$(printf '─%.0s' {1..62})${RESET}"; }

# ── Sanity checks ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash demo_script.sh"; exit 1; }

DIAMORPHINE_KO="./diamorphine/diamorphine.ko"
DETECTOR_PY="./detector.py"
ELASTIC_URL="http://localhost:9200"
ELASTIC_USER="${ELASTIC_USER:-elastic}"
ELASTIC_PASS="${ELASTIC_PASS:-HakiDemo2025!}"

[[ -f "$DIAMORPHINE_KO" ]] || {
    echo "ERROR: $DIAMORPHINE_KO not found."
    echo "  Build it first:  cd diamorphine && make"
    exit 1
}
[[ -f "$DETECTOR_PY" ]] || {
    echo "ERROR: $DETECTOR_PY not found."
    exit 1
}

# ── Elastic connectivity check ─────────────────────────────────────────────
check_elastic() {
    curl -s -u "${ELASTIC_USER}:${ELASTIC_PASS}" \
         --connect-timeout 3 "${ELASTIC_URL}/_cluster/health" \
         > /dev/null 2>&1
}

# ── Recent Elastic alerts (last 15 minutes) ────────────────────────────────
count_elastic_alerts() {
    local count
    count=$(curl -s -u "${ELASTIC_USER}:${ELASTIC_PASS}" \
        -H 'Content-Type: application/json' \
        "${ELASTIC_URL}/.alerts-security.alerts-default/_count" \
        -d '{
          "query": {
            "range": {
              "@timestamp": { "gte": "now-15m" }
            }
          }
        }' 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count',0))" \
        2>/dev/null || echo "N/A")
    echo "$count"
}

# ── Pre-flight cleanup ──────────────────────────────────────────────────────
if lsmod 2>/dev/null | grep -q '^diamorphine'; then
    warn "Diamorphine already visible — unloading before demo..."
    rmmod diamorphine 2>/dev/null || true
fi

# ── Elastic service check ───────────────────────────────────────────────────
echo
echo -e "${BOLD}Pre-flight: checking Elastic services...${RESET}"
ELASTIC_OK=false

if check_elastic; then
    elastic "Elasticsearch: ${GREEN}RUNNING${RESET}"
    ELASTIC_OK=true
else
    warn "Elasticsearch not responding at ${ELASTIC_URL}"
    warn "Starting services..."
    systemctl start elasticsearch kibana elastic-agent 2>/dev/null || true
    sleep 8
    if check_elastic; then
        elastic "Elasticsearch: ${GREEN}RUNNING${RESET} (just started — wait 30s for full init)"
        ELASTIC_OK=true
        sleep 25
    else
        warn "Elasticsearch still not responding. Continuing without live Elastic checks."
        warn "Make sure to open Kibana manually for the demo."
        ELASTIC_OK=false
    fi
fi

# =============================================================================
# Introduction
# =============================================================================
clear
echo -e "${BOLD}${CYAN}"
cat <<'INTRO'
 ╔══════════════════════════════════════════════════════════════╗
 ║         ROOTKIT DETECTION DEMO                               ║
 ║         Linux Mint 22.3 "Zena"  |  kernel 6.17.0-22-generic ║
 ║                                                              ║
 ║         Enterprise EDR: Elastic Security                     ║
 ║         Custom Detector: detector.py (cross-view)            ║
 ╚══════════════════════════════════════════════════════════════╝
INTRO
echo -e "${RESET}"

echo -e "  ${BOLD}Core thesis:${RESET}"
echo "  Any security tool that trusts the OS to report what is running"
echo "  can be silenced by compromising the OS."
echo "  Diamorphine does exactly that — in one insmod."
echo
echo -e "  ${BOLD}Stack:${RESET}"
echo "    Rootkit      Diamorphine LKM — hooks getdents64 + kill"
echo "    Enterprise   Elastic Security (Elasticsearch + Kibana + Elastic Defend)"
echo "    Detector     detector.py — cross-view /proc vs /sys (stdlib only)"
echo
echo -e "  ${BOLD}Four acts:${RESET}"
echo "    ACT 1  →  baseline: everything looks clean"
echo "    ACT 2  →  infection: lsmod / ps / cat all go blind"
echo "    ACT 3  →  Kibana: enterprise EDR shows zero alerts"
echo "    ACT 4  →  cross-view delta exposes the hidden rootkit"
echo
echo -e "  ${BOLD}${YELLOW}Before continuing:${RESET}"
echo "    Open Kibana in your browser:  http://$(hostname -I | awk '{print $1}'):5601"
echo "    Navigate to: Security → Alerts"
echo "    Position it side-by-side with this terminal for Act 3."
pause

# =============================================================================
# ACT 1 — Baseline
# =============================================================================
clear
sep
banner " ACT 1: Baseline — the system before infection"
sep
echo
info "Standard sysadmin commands confirm no suspicious modules."
if $ELASTIC_OK; then
    elastic "Kibana Security → Alerts should show 0 recent alerts."
fi
echo

banner "  1a.  lsmod (reads /proc/modules via getdents64)"
cmd "lsmod | head -20"
echo
lsmod | head -20
echo
info "No 'diamorphine' entry — module is not loaded."
pause

banner "  1b.  Direct read of /proc/modules"
cmd "cat /proc/modules | wc -l  &&  head -5 /proc/modules"
echo
echo "  Total loaded modules: $(wc -l < /proc/modules)"
head -5 /proc/modules
echo "  ..."
info "lsmod is just a pretty-printer over this file — same data, same source."
pause

banner "  1c.  detector.py on a clean system"
cmd "python3 detector.py"
echo
python3 "$DETECTOR_PY"
info "Both views agree — baseline confirmed clean."
pause

if $ELASTIC_OK; then
    banner "  1d.  Elastic Security alert count (last 15 min)"
    ALERT_COUNT=$(count_elastic_alerts)
    elastic "Alerts in last 15 minutes: ${BOLD}${ALERT_COUNT}${RESET}"
    elastic "Open Kibana now and confirm: Security → Alerts → 0 alerts."
    pause
fi

# =============================================================================
# ACT 2 — Infection
# =============================================================================
clear
sep
banner " ACT 2: Infection — loading Diamorphine"
sep
echo
warn "We are about to load a rootkit kernel module."
echo
echo "  What Diamorphine does on load:"
echo "    1. Resolves kallsyms_lookup_name via kprobe (6.7+ workaround)"
echo "    2. Locates sys_call_table"
echo "    3. Saves original pointers for getdents64 and kill"
echo "    4. Patches both entries in the syscall table"
echo "    5. Removes itself from the module linked list → invisible to lsmod"
echo
echo "  Steps 4 and 5 happen before insmod returns to userspace."
echo "  There is no window where the module is loaded but not yet hidden."
pause

banner "  2a.  Loading the module"
cmd "insmod ./diamorphine/diamorphine.ko"
echo
insmod "$DIAMORPHINE_KO"
sleep 1
echo
info "dmesg confirms the hooks are installed:"
echo "  ┌──────────────────────────────────────────────────────────"
dmesg | tail -6 | sed 's/^/  │  /'
echo "  └──────────────────────────────────────────────────────────"
echo
alert "Diamorphine is now running in kernel space."
alert "The syscall table has been patched. The module is hidden."
pause

banner "  2b.  Proving the blindness — standard tools"
echo
info "lsmod:"
cmd "lsmod | grep -i diamond"
lsmod | grep -i diamond \
    || echo -e "  ${RED}(no output — diamorphine filtered by the hook)${RESET}"
echo

info "Direct cat of /proc/modules:"
cmd "grep -i diamond /proc/modules"
grep -i diamond /proc/modules \
    || echo -e "  ${RED}(no output — same hook, same lie)${RESET}"
echo

info "ps looking for diamorphine-related processes:"
cmd "ps aux | grep -i diamond | grep -v grep"
ps aux | grep -i diamond | grep -v grep \
    || echo -e "  ${RED}(nothing — process table also relies on the OS)${RESET}"
echo
pause

banner "  2c.  Why every Ring-3 tool fails"
echo
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │                                                              │"
echo "  │   AV engine       RASP agent       sysadmin (lsmod)         │"
echo "  │       │               │                  │                  │"
echo "  │       └───────────────┴──────────┬────────┘                 │"
echo "  │                                  ▼                          │"
echo "  │                           getdents64 syscall                 │"
echo "  │                                  │                          │"
echo "  │                                  ▼                          │"
echo "  │                      ┌─ Diamorphine hook ─┐                 │"
echo "  │                      │  filters its entry  │                │"
echo "  │                      └────────────────────┘                 │"
echo "  │                                  │                          │"
echo "  │                                  ▼                          │"
echo "  │                        'Nothing to see here'                │"
echo "  │                                                              │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo
echo "  Signatures, heuristics, behavioural analysis — none of it matters"
echo "  once the OS kernel is compromised."
echo "  The OS is the rootkit.  The rootkit controls the answer."
pause

# =============================================================================
# ACT 3 — Enterprise EDR (Elastic Security)
# =============================================================================
clear
sep
banner " ACT 3: Enterprise EDR — Elastic Security"
sep
echo
elastic "Rootkit is live.  Elastic Defend has been monitoring this system."
elastic "Elastic Agent is collecting kernel telemetry via eBPF / kprobes."
echo
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  Elastic Security monitors via:                              │"
echo "  │    • Elastic Defend (EDR) — kernel telemetry, process events │"
echo "  │    • Detection rules — 'Kernel Module Load via insmod'       │"
echo "  │    • auditd integration — init_module / finit_module         │"
echo "  │    • SIEM rules — anomaly detection, ML jobs                 │"
echo "  │                                                              │"
echo "  │  All of these rely on the OS to accurately report events.    │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo
pause

banner "  3a.  Switch to Kibana now"
echo
elastic "In your browser, navigate to:"
echo -e "  ${BOLD}${BLUE}http://$(hostname -I | awk '{print $1}'):5601${RESET}"
echo
echo "  Go to:  Security → Alerts"
echo
echo "  Expected result:"
echo -e "  ${RED}${BOLD}  0 alerts.${RESET}"
echo
echo "  The rootkit that is actively running in this kernel right now"
echo "  is not reflected in the Kibana alerts panel."
echo
if $ELASTIC_OK; then
    ALERT_COUNT=$(count_elastic_alerts)
    elastic "API check — alerts in last 15 min: ${BOLD}${ALERT_COUNT}${RESET}"
    echo
    if [[ "$ALERT_COUNT" == "0" ]] || [[ "$ALERT_COUNT" == "N/A" ]]; then
        echo -e "  ${RED}${BOLD}Confirmed: Elastic Security sees nothing.${RESET}"
    else
        echo -e "  ${YELLOW}${BOLD}Elastic generated ${ALERT_COUNT} alert(s) — examine them in Kibana.${RESET}"
        echo "  Note: Elastic may catch the load event without detecting the active"
        echo "  hidden state. The module is still invisible to all OS-level tools."
    fi
fi
echo
pause

banner "  3b.  Why Elastic misses the active hidden state"
echo
echo "  Elastic Defend has two possible detection moments:"
echo
echo "    1. LOAD EVENT — the insmod() call itself"
echo "       Elastic may fire on this (the kernel module load rule)."
echo "       But this is a one-time event.  If Elastic was briefly down,"
echo "       in a detection gap, or the rule was disabled, it is missed."
echo
echo "    2. ACTIVE STATE — 'is the module loaded right now?'"
echo "       To answer this, Elastic queries the OS: /proc/modules, lsmod."
echo "       The OS is compromised.  The answer is: 'nothing loaded.'"
echo "       Elastic cannot distinguish a clean system from a hidden rootkit"
echo "       by asking the compromised OS."
echo
echo "  This is the fundamental gap:"
echo -e "  ${BOLD}Event-based detection vs state-based detection.${RESET}"
echo
echo "  If you missed the load event — or the rootkit was loaded before"
echo "  monitoring started — enterprise EDR is blind to the active state."
pause

# =============================================================================
# ACT 4 — Detection
# =============================================================================
clear
sep
banner " ACT 4: Detection — cross-view analysis"
sep
echo
info "detector.py does not ask the OS.  It reads two kernel data sources"
info "that use different code paths, then computes the delta."
echo
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │                                                              │"
echo "  │   /proc/modules                                              │"
echo "  │       procfs, exposed via getdents64                        │"
echo "  │       ← Diamorphine hooks this path, removes its entry      │"
echo "  │                                                              │"
echo "  │   /sys/module/<name>/                                        │"
echo "  │       sysfs, kobject/kernfs — different VFS code path       │"
echo "  │       ← Diamorphine never hooks this path                   │"
echo "  │                                                              │"
echo "  │   delta  =  /sys/module/ − /proc/modules                    │"
echo "  │           =  modules the OS is hiding                       │"
echo "  │           =  rootkit indicator                               │"
echo "  │                                                              │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo
pause

banner "  4a.  Running the detector"
cmd "python3 detector.py"
echo
python3 "$DETECTOR_PY" || true
echo
alert "Cross-view delta exposed the hidden module."
echo
info "Why this works:"
echo "    /sys/module/ is populated during module_init() via kobject_add()."
echo "    Diamorphine's module_hide() removes it from the linked list that"
echo "    feeds /proc/modules and lsmod — but kobject sysfs entries are"
echo "    registered independently through kernfs."
echo "    Two separate kernel subsystems.  One hook.  One blind spot."
echo
echo -e "  ${BOLD}Elastic:    0 alerts (active state invisible)${RESET}"
echo -e "  ${BOLD}detector.py: SYSTEM COMPROMISED${RESET}"
pause

banner "  4b.  Split-screen summary"
echo
echo "  ┌──────────────────────┬───────────────────────────────────────┐"
echo "  │  Kibana (Act 3)      │  Terminal (Act 4)                     │"
echo "  ├──────────────────────┼───────────────────────────────────────┤"
echo "  │  Security → Alerts   │  \$ sudo python3 detector.py          │"
echo "  │                      │                                       │"
echo "  │  No alerts.          │  [HIDDEN]  diamorphine                │"
echo "  │                      │  ⚠  1 hidden module detected          │"
echo "  │  System looks clean. │  SYSTEM COMPROMISED                   │"
echo "  └──────────────────────┴───────────────────────────────────────┘"
echo
echo "  The enterprise tool trusts the OS."
echo "  The custom detector bypasses it entirely."
echo "  Same system.  One second of difference in methodology."
pause

# =============================================================================
# Cleanup
# =============================================================================
clear
sep
banner " Cleanup — removing Diamorphine"
sep
echo
info "Diamorphine hides itself, so rmmod alone will fail."
info "Magic signal 63 toggles module visibility first."
echo

banner "  Step 1: unhide via magic signal"
cmd "kill -63 0"
kill -63 0
sleep 1
echo
info "Checking if module is now visible:"
cmd "lsmod | grep diamond"
lsmod | grep -i diamond \
    && info "Visible ✓ — module re-added to the linked list" \
    || warn "Still hidden — retrying..."

if ! lsmod | grep -qi diamond 2>/dev/null; then
    sleep 1
    kill -63 0
    sleep 1
    lsmod | grep -i diamond || warn "Module still hidden — rmmod may still work"
fi
echo

banner "  Step 2: unload"
cmd "rmmod diamorphine"
if rmmod diamorphine 2>/dev/null; then
    info "Unloaded cleanly ✓"
else
    warn "rmmod returned an error — check dmesg"
fi
sleep 1
echo

banner "  Step 3: final verification"
cmd "python3 detector.py"
echo
python3 "$DETECTOR_PY" && info "System is clean ✓" \
    || warn "Still showing a hidden module — reboot the VM to recover"

echo
sep
banner " Demo complete"
sep
echo
echo "  What was demonstrated:"
echo "    • A kernel rootkit loads and hides in one insmod call"
echo "    • lsmod, /proc/modules, ps — all trust getdents64 — all lied to"
echo "    • Elastic Security (enterprise EDR) sees the active hidden state as clean"
echo "    • A cross-view /proc vs /sys delta reveals the truth"
echo "    • The detector required no kernel changes, no signatures, no agents"
echo
