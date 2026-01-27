# Slurm Docker Cluster – OpenMPI Extension

This repository is a **didactic extension** of  
**[Slurm Docker Cluster](https://github.com/giovtorres/slurm-docker-cluster)** by Giovanni Torres.

It adds **OpenMPI support** on top of the existing Slurm Docker cluster while **preserving full upstream compatibility**.  
The goal is to provide a **ready-to-use environment for teaching and experimenting with parallel programming** using:

- Slurm
- OpenMP
- MPI (OpenMPI)
- Hybrid MPI + OpenMP workloads

---

## 🎯 Scope and Design Principles

This fork follows a few strict principles:

- ✅ **No invasive changes** to the upstream Dockerfile
- ✅ **Layered extension** via derived images
- ✅ **Upstream updates remain easy to merge**
- ✅ **HPC-correct usage patterns** (`srun`, not `mpirun`)
- ✅ Suitable for **courses, labs, and demos**

---

## 🧱 What Is Included

| Component | Status |
|---------|-------|
| Slurm | ✅ from upstream |
| OpenMP | ✅ via GCC |
| OpenMPI | ➕ added in this fork |
| Multi-node MPI | ✅ |
| Hybrid MPI + OpenMP | ✅ |
| Docker Compose | ✅ |
| Makefile workflows | ✅ |

---

## 🏗️ Architecture Overview

The cluster consists of the following services:

- `mysql` – accounting database
- `slurmdbd` – Slurm accounting daemon
- `slurmctld` – Slurm controller
- `slurmrestd` – REST API (optional for teaching)
- `c1`, `c2` – compute nodes (`slurmd`)

A shared `/data` directory is mounted across all nodes for job files and binaries.

---

## 🚀 Quick Start

### Requirements
- Docker
- Docker Compose
- GNU Make

### Clone the repository
```bash
git clone <your-fork-url>
cd slurm-docker-cluster

### Clone the repository
```bash
# Build base Slurm image first
COMPOSE_BAKE=false docker compose build slurmdbd

# Build OpenMPI-enabled services
COMPOSE_BAKE=false docker compose build slurmctld c1 c2

# Start the cluster
docker compose up -d

### Verifying the Installation
```bash
make shell
