# Windows in the browser on Railway: dockur/windows (QEMU) with a gate that
# refuses to start on services too small to run it (see gate.sh).
FROM dockurr/windows:6.06

# KVM=N: Railway has no /dev/kvm, so QEMU emulates the CPU (TCG).
# PROTECT=Y: dockur's web viewer asks for USERNAME/PASSWORD, the same login as
# the Windows account. ALLOCATE=N: the 64 GB disk grows as Windows writes.
ENV VERSION=2022 \
    KVM=N \
    PROTECT=Y \
    USERNAME=admin \
    RAM_SIZE=4G \
    CPU_CORES=4 \
    DISK_SIZE=64G \
    ALLOCATE=N

# Railway's healthcheck at /healthcheck, without the login. dockur turns every
# "auth_basic off" into a login when PROTECT is on, so this one is spaced differently.
RUN sed -i 's#^    location / {#    location = /healthcheck {\n      auth_basic   off;\n      return 200 "ok";\n    }\n\n    location / {#' \
      /etc/nginx/default.conf \
  && grep -q 'location = /healthcheck' /etc/nginx/default.conf

COPY gate.sh /gate.sh
RUN chmod +x /gate.sh

EXPOSE 8006 3389
ENTRYPOINT ["/usr/bin/tini", "-s", "/gate.sh"]
