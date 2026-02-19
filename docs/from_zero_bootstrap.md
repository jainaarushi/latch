# From-Zero Bootstrap (Bare GPU Host)

Use this on a fresh Ubuntu GPU VM where even NVIDIA tooling is not installed.

## One command

```bash
make bootstrap-from-zero
```

This runs:

1. `scripts/bootstrap_gpu_host.sh`
2. `scripts/bootstrap_k8s_gpu.sh`
3. `scripts/full_setup.sh` (unless `RUN_APP_SETUP=false`)

## Optional controls

- Driver package:
  - `DRIVER_PACKAGE=nvidia-driver-550 make bootstrap-gpu-host`
- Force reinstall driver:
  - `FORCE_DRIVER_INSTALL=true make bootstrap-gpu-host`
- MIG strategy for plugin:
  - `MIG_STRATEGY=single make bootstrap-k8s-gpu`
- Skip app deployment and only prep machine/cluster:
  - `RUN_APP_SETUP=false make bootstrap-from-zero`

## Notes

- Scripts assume Ubuntu/Debian-style `apt-get` and `sudo`.
- If driver is newly installed, a reboot may be required before `nvidia-smi` works.
- After reboot, rerun:

```bash
make bootstrap-k8s-gpu
make full-setup
```
