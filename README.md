# Deploy and Host Windows on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/windows?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=windows)

This template runs a Windows desktop on Railway and streams it to your browser. It needs a Railway Pro plan (see below). By default it's Windows Server 2022 with the Desktop Experience. On first boot it downloads the installer from Microsoft and installs Windows unattended. After that you log in from any device and get a normal Windows desktop with Edge, PowerShell and everything you install, kept on a volume.

## About Hosting Windows

Windows runs in a QEMU virtual machine, packaged by the open source [dockur/windows](https://github.com/dockur/windows) project. Railway offers no hardware virtualization (KVM), so QEMU emulates the CPU. It works, but it's several times slower than a Windows VPS: fine for running a Windows-only tool, testing a site in Edge, or a scheduled job, and not for gaming or heavy apps.

The browser desktop and Remote Desktop are both protected by the Windows account in `USERNAME` and `PASSWORD`. The virtual disk lives on the volume at `/storage`, so installed software and files survive redeploys.

## Common Use Cases

- Run a Windows-only program or utility without owning a Windows machine
- Test websites in Edge on Windows from a Mac, Linux machine or Chromebook
- Keep a small always-on Windows box for scheduled tasks or scripts
- Try Windows Server features in a disposable environment

## Dependencies for Windows Hosting

- None. It's a single service with a volume.

### Deployment Dependencies

- [dockur/windows](https://github.com/dockur/windows) (QEMU, noVNC web viewer)
- Windows evaluation media, downloaded from Microsoft on first boot

### Implementation Details

**It needs a Pro plan.** Windows uses `RAM_SIZE` (4 GB by default) plus about 2 GB for the emulator, and the first install needs about 30 GB of disk. Railway caps volumes at 5 GB on Hobby, while Pro volumes start at 50 GB. The template checks both when it starts:

- If the memory limit or the volume is too small, it shows a page saying what's missing instead of starting Windows. So a deploy on Free, Trial or Hobby doesn't crash; it just explains why Windows can't run there.
- On Pro, if the volume was made smaller than 30 GB, resize it: click the volume on the canvas and open *Settings*. Railway resizes volumes live, and Windows starts by itself once there's room.

**First boot takes a while.** Open your Railway domain and log in with `USERNAME` and `PASSWORD` from the Variables tab. The page shows the download, then the installer running. Under emulation the full install took about half an hour in our tests on one Railway host and well over an hour on a slower one, after which the desktop appears. Don't redeploy or restart the service meanwhile: an interrupted install starts over. Later boots go straight to the desktop.

**Remote Desktop:** the template adds a TCP proxy for port 3389. Find its address under *Settings → Networking*, then connect any RDP client to `<domain>.proxy.rlwy.net:<port>` with the same login. RDP feels faster than the browser viewer. While a Remote Desktop session is signed in, the browser view shows the lock screen.

**Choosing a version:** set `VERSION` before the first boot. Options are `2022` (default), `2025`, `2019`, `11`, `10`, `11l` and `10l` (the LTSC editions). Changing it later doesn't reinstall; delete the files on the volume first if you want a fresh install.

**Licensing:** Windows is downloaded from Microsoft as an evaluation edition. Server editions run for 180 days and Enterprise editions for 90 days, unless you activate them with your own license key. You're responsible for licensing the copy you run.

**Cost:** an always-on service with about 6 GB of memory and a few busy vCPUs costs noticeably more than a typical web app. Check usage in the first days, and shut Windows down from the Start menu when you don't need it.

**Shutting down:** when you shut Windows down from the Start menu, the emulated PC turns off and the service stays up on a small page that says so, using almost no CPU or memory. Your disk stays on the volume. To boot Windows again, restart the deployment (*Deployments*, then *Restart* in the active deployment's menu). Before you restart or redeploy the service yourself, shut Windows down from the Start menu first: Railway's *Restart* stops the container within seconds, which for Windows is like pulling the plug.

**Disk size:** the Windows disk is sized to the volume, leaving room for the installer: about 38 GB on a 50 GB volume, and 64 GB at most. It only takes up what Windows has written. For a bigger disk, resize the volume, set `DISK_SIZE` (for example `120G`), restart, and extend the C: partition in Disk Management.

**Limits:**

- CPU emulation: expect it to be slower than a real PC.
- No GPU, no nested virtualization (WSL 2 and Hyper-V won't run), no USB devices.

Windows is a trademark of Microsoft. This community template is not affiliated with or endorsed by Microsoft or the dockur project.

**Other templates by the same author:** for a lighter desktop, see the Linux Desktops on [Ubuntu](https://railway.com/deploy/linux-desktop?referralCode=sLjDXb) and [Linux Mint](https://railway.com/deploy/mint?referralCode=sLjDXb), or the [Linux](https://railway.com/deploy/linux?referralCode=sLjDXb) server template.

## Why Deploy Windows on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Windows on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
