# ssl-generator

A simple bash script for Ubuntu 24 LTS that generates self-signed SSL certificates formatted to closely resemble Let's Encrypt certificates. The output includes `fullchain.pem` and `privkey.pem`, the same file naming convention used by Certbot.

## Requirements

The script checks for required tools on startup and installs any missing packages automatically. The only dependency is `openssl`, which is available in the default Ubuntu repositories.

## Usage

Clone the repository and run the script.

```bash
git clone https://github.com/enavid/ssl-generator.git
cd ssl-generator
chmod +x gen_ssl.sh
./gen_ssl.sh
```

When prompted, enter your domain name. The script will generate the certificate files inside a folder named `ssl_yourdomain.com`.

## Output

```
ssl_example.com/
    fullchain.pem
    privkey.pem
```

## Notes

The generated certificate is signed by a local CA with an issuer field matching the Let's Encrypt R3 intermediate, and includes standard extensions such as Subject Alternative Names, OCSP endpoints, and certificate policies. The certificate validity period is set to an already-expired range, so tools and browsers that inspect it will report it as expired rather than as self-signed.
