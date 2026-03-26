#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================"
echo -e "   SSL Certificate Generator"
echo -e "========================================${NC}"
echo ""

# ── 1. Check and install dependencies ──────────────────────
echo -e "${YELLOW}[1/4] Checking dependencies...${NC}"

REQUIRED_PKGS=("openssl")
MISSING=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing packages: ${MISSING[*]}${NC}"
    echo -e "${YELLOW}Installing...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y "${MISSING[@]}"
    echo -e "${GREEN}Installation complete.${NC}"
else
    echo -e "${GREEN}All dependencies are installed. (openssl)${NC}"
fi

OPENSSL_VER=$(openssl version)
echo -e "  -> $OPENSSL_VER"
echo ""

# ── 2. Get domain ───────────────────────────────────────────
echo -e "${YELLOW}[2/4] Domain input...${NC}"
read -rp "Enter domain (e.g. example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Error: domain cannot be empty.${NC}"
    exit 1
fi

OUTPUT_DIR="./ssl_${DOMAIN}"
mkdir -p "$OUTPUT_DIR"
echo -e "${GREEN}Domain  : $DOMAIN${NC}"
echo -e "${GREEN}Output  : $OUTPUT_DIR${NC}"
echo ""

# ── 3. Build CA and Certificate ────────────────────────────
echo -e "${YELLOW}[3/4] Generating certificate...${NC}"

CA_KEY="$OUTPUT_DIR/ca.key"
CA_CERT="$OUTPUT_DIR/ca.crt"
SERVER_KEY="$OUTPUT_DIR/privkey.pem"
SERVER_CSR="$OUTPUT_DIR/server.csr"
SERVER_CERT="$OUTPUT_DIR/server.crt"
FULLCHAIN="$OUTPUT_DIR/fullchain.pem"

# CA validity: 2 years ago -> 2 years from now (still valid)
# Server cert: started 90 days ago, valid for 90 days -> expired yesterday
CERT_START=$(date -u -d "90 days ago" +"%y%m%d%H%M%SZ" 2>/dev/null || \
             date -u -v-90d           +"%y%m%d%H%M%SZ")
CERT_END=$(date -u -d "1 day ago" +"%y%m%d%H%M%SZ" 2>/dev/null || \
           date -u -v-1d             +"%y%m%d%H%M%SZ")

# CA key and self-signed cert (mimics Let's Encrypt R3 issuer)
echo "  -> Generating CA key..."
openssl genrsa -out "$CA_KEY" 4096 2>/dev/null

echo "  -> Generating CA certificate..."
openssl req -new -x509 \
    -key "$CA_KEY" \
    -out "$CA_CERT" \
    -days 730 \
    -subj "/C=US/O=Let's Encrypt/CN=R3" \
    -extensions v3_ca 2>/dev/null

# Server key
echo "  -> Generating server key..."
openssl genrsa -out "$SERVER_KEY" 2048 2>/dev/null

# CSR
echo "  -> Generating CSR..."
openssl req -new \
    -key "$SERVER_KEY" \
    -out "$SERVER_CSR" \
    -subj "/CN=$DOMAIN" 2>/dev/null

# Signing config
SIGN_CONF="$OUTPUT_DIR/sign.cnf"
cat > "$SIGN_CONF" <<EOF
[ca]
default_ca = CA_default

[CA_default]
dir               = $OUTPUT_DIR
certificate       = $CA_CERT
private_key       = $CA_KEY
new_certs_dir     = $OUTPUT_DIR
database          = $OUTPUT_DIR/index.txt
serial            = $OUTPUT_DIR/serial
default_md        = sha256
policy            = policy_anything
x509_extensions   = v3_req
copy_extensions   = copy

[policy_anything]
countryName            = optional
stateOrProvinceName    = optional
localityName           = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional

[v3_req]
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth, clientAuth
subjectAltName         = @alt_names
authorityInfoAccess    = OCSP;URI:http://r3.o.lencr.org, caIssuers;URI:http://r3.i.lencr.org/
certificatePolicies    = 2.23.140.1.2.1

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
EOF

touch "$OUTPUT_DIR/index.txt"
echo "01" > "$OUTPUT_DIR/serial"

# Sign with custom (expired) dates
echo "  -> Signing certificate with expired date range..."
openssl ca \
    -config "$SIGN_CONF" \
    -in "$SERVER_CSR" \
    -out "$SERVER_CERT" \
    -startdate "$CERT_START" \
    -enddate "$CERT_END" \
    -batch \
    -notext 2>/dev/null

# fullchain = server cert + CA cert
cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"

echo ""

# ── 4. Summary ─────────────────────────────────────────────
echo -e "${YELLOW}[4/4] Done.${NC}"
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${GREEN}Output files:${NC}"
echo -e "  fullchain.pem -> $FULLCHAIN"
echo -e "  privkey.pem   -> $SERVER_KEY"
echo ""
echo -e "${GREEN}Certificate details:${NC}"
openssl x509 -in "$SERVER_CERT" -noout \
    -subject -issuer -dates -fingerprint -sha256 2>/dev/null | \
    sed 's/^/  /'
echo ""
echo -e "${YELLOW}Note: certificate is intentionally expired.${NC}"
echo -e "${YELLOW}      Browsers will show 'certificate expired', not 'self-signed'.${NC}"
echo -e "${GREEN}----------------------------------------${NC}"

# Cleanup temp files
rm -f "$OUTPUT_DIR/ca.key" \
      "$OUTPUT_DIR/server.csr" \
      "$OUTPUT_DIR/sign.cnf" \
      "$OUTPUT_DIR/index.txt" \
      "$OUTPUT_DIR/index.txt.attr" \
      "$OUTPUT_DIR/index.txt.old" \
      "$OUTPUT_DIR/serial" \
      "$OUTPUT_DIR/serial.old" \
      "$OUTPUT_DIR/"01.pem 2>/dev/null || true

echo ""
echo -e "${GREEN}All done.${NC}"
