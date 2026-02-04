# Deployment Guide

This guide explains how to generate an SSH key (if you don’t already have one) and how to pass it to the legacy deployment script.

## Prerequisites

- Azure subscription
- PowerShell with Az module installed
- SSH key pair (public key required)

## 1) Generate an SSH Key (if needed)

Use one of the following commands to create a key pair:

### Generate on Windows (PowerShell)

```powershell
ssh-keygen -t rsa -b 4096 -f $HOME\.ssh\dnsmig -C "dnsmig"
```

### Generate on macOS / Linux (bash)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C "dnsmig"
```

This creates:

- Public key: `dnsmig.pub`
- Private key: `dnsmig`

## 2) Deploy the Legacy Environment

Run the legacy deployment script and provide the public key path:

### Deploy on Windows (PowerShell)

```powershell
./scripts/01-deploy-legacy.ps1 -SshPublicKeyPath "$HOME\.ssh\dnsmig.pub"
```

### Deploy on macOS / Linux (PowerShell)

```powershell
./scripts/01-deploy-legacy.ps1 -SshPublicKeyPath "$HOME/.ssh/dnsmig.pub"
```

## 3) Next Steps

Continue with the runbook:

- [docs/Migration-Runbook.md](Migration-Runbook.md)
