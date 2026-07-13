---
apply: always
---

Canonical hardware specs for this device live in [HARDWARE.md](../../HARDWARE.md).
Specs can go stale — re-verify live state before trusting them for anything
load-bearing:

```bash
tnctl device rtx2000-ada-128gb-se
tnctl ssh rtx2000-ada-128gb-se
```

Do not repeat the sibling `openclaw-helm` repo's Blackwell/NVFP4 GPU claim for this
device — it's Ada Lovelace, not Blackwell. See HARDWARE.md for details.
