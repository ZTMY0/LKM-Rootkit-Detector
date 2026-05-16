# LKM Rootkit Detector

Demonstrates that an enterprise EDR trusting the OS for ground truth can be silenced by a kernel rootkit — and detects it via a cross-view diff that bypasses the compromised path.

**Platform:** Linux Mint 22.3 · kernel `6.17.0-22-generic`  
**Rootkit:** Diamorphine · **EDR:** Elastic Security

---

## How it works

Diamorphine hooks `getdents64` to hide itself from `/proc/modules`. `lsmod`, Elastic's scanner, and every standard tool read this path — they all get the filtered answer.

`/sys/module/` is managed by a separate kernel subsystem that Diamorphine never touches. The module directory stays there.

```
/proc/modules  ← hooked    →  124 modules (diamorphine absent)
/sys/module/   ← untouched →  125 entries (diamorphine present)
delta = 1  →  hidden module found
```

`detector.py` computes this diff. No dependencies, no signatures, no kernel changes.

---

## Usage

```bash

cd diamorphine && make

# Run the detector
sudo python3 detector.py           # single scan
sudo python3 detector.py --watch   # continuous
sudo python3 detector.py --json    # machine-readable

# Load / hide
sudo insmod diamorphine/diamorphine.ko

# Unhide and remove
sudo kill -63 0 && sudo rmmod diamorphine
```

Exit `0` = clean · Exit `1` = hidden module detected.

---

## Demo

```bash
sudo bash demo_script.sh
```

| Act | Result |
|-----|--------|
| Baseline | All tools + Kibana report clean |
| Load rootkit | `lsmod` goes blind, Kibana: 0 alerts |
| Run detector | `SYSTEM COMPROMISED — diamorphine` |

See `ELASTIC_SETUP.md` for the full Elasticsearch + Kibana + Elastic Agent install.

---

## References

- [Diamorphine](https://github.com/m0nad/Diamorphine) · [kprobes docs](https://www.kernel.org/doc/html/latest/trace/kprobes.html) · [Elastic Security](https://www.elastic.co/security)