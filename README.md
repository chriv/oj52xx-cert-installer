# HP OfficeJet 52xx Certificate Installer

A Bash-based automation tool to push Let's Encrypt certificates to HP OfficeJet 5200 Series printers (and compatible models).

This script bridges the gap between a standard Certbot setup and the HP Embedded Web Server (EWS). It takes an existing PEM certificate/key pair, packages them into a password-protected PFX (PKCS#12) file, authenticates to the printer, and uploads the certificate.

## Prerequisites

Before installing, ensure your environment meets the following requirements.

### 1. DNS Resolution
The script communicates with the printer via its Fully Qualified Domain Name (FQDN).
* **DNS (Recommended):** Ensure your local DNS server resolves the printer's hostname (e.g., `printer.examle.com`) to the printer's IP address. This ensures all clients on the network can verify the certificate.
* **Hosts File:** Alternatively, add an entry to `/etc/hosts` on the machine running this script, though this is not recommended.

### 2. Valid Certificates (Certbot)
This script **does not** issue certificates. It installs certificates that you have already obtained.
* You must have `certbot` (or another ACME client) running on this machine.
* A valid certificate and private key must exist in a directory accessible by root (default: `/etc/letsencrypt/live/<PRINTER_FQDN>/`).
* **Note:** The script expects standard Let's Encrypt naming conventions (`fullchain.pem` and `privkey.pem`).

## Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/chriv/oj52xx-cert-installer.git
    cd oj52xx-cert-installer
    ```

2.  **Configure credentials:**
    Copy the sample configuration file and edit it to match your environment.
    ```bash
    cp config.env.sample config.env
    nano config.env
    ```

    **Configuration Variables:**
    * `PHOST`: Printer hostname (e.g., `printer`).
    * `PDOM`: Printer domain (e.g., `example.com`).
    * `PUSER`: Printer admin username (usually `admin`).
    * `PPASS`: Printer admin password.
    * `LELIVE`: Path to your certificate directory (default: `/etc/letsencrypt/live`).
    * `INSECURE`: Set to 1 anytime the current printer certificate is expected to currently be invalid. Set to 0 if it's expected to be valid.
    * `DRY_RUN`: Allows script/service to do all steps except upload the certificate package to the printer if set to 1.
    * `VERBOSE`: Makes the curl command give verbose output for troubleshooting purposes.

3.  **Run the installer:**
    ```bash
    chmod +x setup.sh oj52xx-cert.sh
    sudo ./setup.sh
    ```

    **What the installer does:**
    * Forces an immediate "Insecure" run to install the certificate (bypassing any existing expired/self-signed cert errors on the printer).
    * Installs the script to `/usr/local/bin/oj52xx-cert`.
    * Installs the config to `/etc/oj52xx-cert/config.env` with restricted permissions (0600).
    * Enables a systemd timer to check/update the certificate weekly.

## Usage

**Automatic Updates:**
The systemd timer runs daily. It will generate a new ephemeral PFX file from your current Let's Encrypt files and push it to the printer.

**Manual Run:**
To force a run immediately:
```bash
sudo systemctl start oj52xx-cert.service
```

**Check Status & Logs:**
```bash
systemctl status oj52xx-cert.service
journalctl -u oj52xx-cert.service
```

## Security Notes

* **Root Privileges:** The script requires root privileges because it must read the private keys in `/etc/letsencrypt/live/`.
* **Secrets:** The printer password is stored in `/etc/oj52xx-cert/config.env`. This file is locked down (read/write by root only).
* **Temporary Files:** The script generates a temporary PFX file and a cookie jar in `/tmp` during execution. These are created with restricted permissions (0600) and are deleted immediately upon completion.
