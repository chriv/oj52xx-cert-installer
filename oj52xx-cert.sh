#!/bin/bash
# Name: oj52xx-cert.sh
# Date: 2025-11-21 (Refactored)
# Author: Chuck Renner
# License: MIT License
# Version: 0.2.0

# --- 1. SAVE ENVIRONMENT ---
OVERRIDE_INSECURE=${INSECURE:-}

# --- 2. CONFIG LOADING ---
if [[ -f "./config.env" ]]; then
    source "./config.env"
elif [[ -f "/etc/oj52xx-cert/config.env" ]]; then
    source "/etc/oj52xx-cert/config.env"
else
    echo "Error: Configuration file not found." >&2
    exit 1
fi

# --- 3. RESTORE ENVIRONMENT ---
if [[ -n "$OVERRIDE_INSECURE" ]]; then
    INSECURE="$OVERRIDE_INSECURE"
fi

# Exit if script is not running with root privileges.
if [ `id -u` -ne 0 ]; then
  echo "Run this script using sudo!"
  exit 1
fi

# Define functions
function str_random() {
    array=()
    for i in {a..z} {A..Z} {0..9}; do
        array[$RANDOM]=$i
    done
    printf %s ${array[@]::8}
}
function urlencode() {
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    LC_COLLATE=$old_lc_collate
}

INSECURE_OPTION=
VERBOSE_OPTION=
if [ ${INSECURE:-0} -eq 1 ]; then INSECURE_OPTION=--insecure; fi
if [ ${VERBOSE:-0} -eq 1 ]; then VERBOSE_OPTION=--verbose; fi

# Temporary directory
DUMPDIR=/tmp
# Generate random password for PFX
PFXPASS=$(str_random)
# Printer FQDN
PFQDN=$PHOST.$PDOM
# File Paths
PFX=$DUMPDIR/$PHOST.pfx
JAR=$DUMPDIR/$PHOST.cjar
OUT=$DUMPDIR/$PHOST
# Encode Creds
PUSER_ENC=$(urlencode "$PUSER")
PPASS_ENC=$(urlencode "$PPASS")

echo "Creating encrypted PFX..."
# Verify LE Certs exist
if [[ ! -f "$LELIVE/$PFQDN/privkey.pem" ]] || [[ ! -f "$LELIVE/$PFQDN/fullchain.pem" ]]; then
    echo "CRITICAL: Let's Encrypt certificates not found at $LELIVE/$PFQDN/"
    exit 1
fi

# Create PFX
openssl pkcs12 -export -out "$PFX" \
    -inkey "$LELIVE/$PFQDN/privkey.pem" \
    -in "$LELIVE/$PFQDN/fullchain.pem" \
    -password "pass:$PFXPASS"
chmod 600 "$PFX"

if [ ! -f "$PFX" ]; then
    echo "CRITICAL: PFX generation failed."
    exit 1
fi
echo "Completed creating PFX."

echo "Authenticating to printer..."

# 1. Authenticate (Session Init)
if ! curl $VERBOSE_OPTION $INSECURE_OPTION --cookie-jar "$JAR" --cookie "$JAR" -u "$PUSER_ENC:$PPASS_ENC" "https://$PFQDN/" --output /dev/null --fail; then
    echo "CRITICAL: Authentication to printer failed."
    rm -f "$PFX" "$JAR"
    exit 1
fi
chmod 600 "$JAR"

# 2. Get Cert Info Page (Pre-flight check)
echo "Checking device certificate info page..."
curl $VERBOSE_OPTION $INSECURE_OPTION --cookie-jar "$JAR" --cookie "$JAR" -u "$PUSER_ENC:$PPASS_ENC" "https://$PFQDN/Security/DeviceCertificates/1/Info" --output /dev/null

# --- DRY RUN CHECK ---
if [ ${DRY_RUN:-0} -eq 1 ]; then
    echo "----------------------------------------------------------------"
    echo "DRY RUN SUCCESSFUL"
    echo "Steps Completed:"
    echo "  1. Generated Encrypted PFX"
    echo "  2. Authenticated to EWS"
    echo "  3. Verified Pre-flight URL"
    echo "Action Skipped: PFX Upload"
    echo "----------------------------------------------------------------"
else
    echo "Pushing encrypted PFX to printer..."

    # 3. Upload PFX
    curl $VERBOSE_OPTION $INSECURE_OPTION --cookie-jar "$JAR" --cookie "$JAR" -u "$PUSER_ENC:$PPASS_ENC" \
        --form "certificate=@$PFX" \
        --form "password=$PFXPASS" \
        --referer "https://$PFQDN/Security/DeviceCertificates/1/Info" \
        "https://$PFQDN/Security/DeviceCertificates/NewCertWithPassword/Upload" --output /dev/null

    # 4. Get Result Page
    curl $VERBOSE_OPTION $INSECURE_OPTION --cookie-jar "$JAR" --cookie "$JAR" -u "$PUSER_ENC:$PPASS_ENC" \
        --referer "https://$PFQDN/Security/DeviceCertificates/NewCertWithPassword/Upload" \
        "https://$PFQDN/Security/DeviceCertificates/1/Info" --output "$OUT-4.html"
    chmod 600 "$OUT-4.html"

    echo "Completed pushing PFX to printer."

    echo "Results highlights from printer certificate information page:"
    if [ -f "$OUT-4.html" ]; then
        grep -E 'SerialNumber|Issuer|ValidityDates|NotBefore|NotAfter|Subject>|Public' "$OUT-4.html" || echo "No cert info found in response."
        rm -f "$OUT-4.html"
    else
        echo "Warning: Result page not retrieved."
    fi
fi

# Cleanup (Runs for both Dry Run and Live)
echo "Cleaning up temporary files..."
rm -f "$PFX" "$JAR"
echo "Done."
