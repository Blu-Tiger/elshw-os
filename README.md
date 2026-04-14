# elshw-os (Essential List Hardware OS)

A minimal, under 20MB, custom Linux distribution that boots directly into a hardware 
information script. No desktop, no package manager — just a kernel, 
an Alpine-based initramfs, and your hardware specs.

## Run via:
- Live OS on USB
- Live OS over PXE
- `sudo bash elshw.sh` directly.

## What it shows
- CPU model, cores, threads, speed
- RAM size, DDR version, speed
- Storage devices (NVMe/SSD/HDD) with sizes
- Network interfaces (Ethernet speed, WiFi standard)
- GPU model and type

### Example output:
```bash
╔══════════════════════════════════════════════════════════╗
║                 SYSTEM HARDWARE CATALOG                  ║
╚══════════════════════════════════════════════════════════╝

▶ 🖥️  PROCESSOR (CPU)
  ├─ Model:       Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz
  ├─ Cores:       8 Physical | 16 Logical
  └─ Speed:       5100 MHz

▶ 🧠 MEMORY (RAM)
  ├─ Size:        16 GB
  ├─ DDR Version: DDR4
  └─ Speed:       3200 MT/s

▶ 💾 INTERNAL STORAGE DEVICES
  ▪ /dev/sda ── 1000 GB [SATA SSD]

▶ 🌐 NETWORK
  ├─ ETH [enp0s31f6]
  │   ├─ MAC:   00:00:00:00:00:00
  │   ├─ IP:    192.168.1.2
  │   └─ Speed: 1000 Mbps  (1 Gbps)
  ├─ Bridge [docker0]  enslaves:
  │   ├─ MAC:   00:00:00:00:00:00
  │   ├─ IP:    172.17.0.1
  │   └─ Speed: Unknown
  └─ WiFi:       No wireless interfaces detected

▶ 🎮 GRAPHICS (GPU)
  ├─ Model: Intel Corporation CometLake-S GT2 [UHD Graphics 630] (rev 05)
  │   └─ Type:  Integrated
  └─ Model: NVIDIA Corporation GP106GL [Quadro P2200] (rev a1)
      └─ Type:  PCIe Gen 3 x16 (8GT/s)
```

## Build

### Install requirements
#### Arch Linux:
```bash
sudo pacman -Syu build-essential base-devel wget mtools dosfstools xorriso
```

#### Debian / Ubuntu:
```bash
sudo apt-get update
sudo apt-get install build-essential wget mtools dosfstools xorriso
```

#### Fedora / RHEL:
```bash
sudo dnf install gcc make elfutils-libelf-devel wget mtools dosfstools xorriso
```

### Download and build
```bash
git clone https://github.com/Blu-Tiger/elshw-os
cd elshw-os
chmod +x build.sh
./build.sh
```

Output: `./iso/elshw-l(limeline-version)-k(kernel-version)-a(alpine-version)-(script-version).iso`


## License
MIT
