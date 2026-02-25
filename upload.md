# Uploading hhi_tracts.pmtiles to Cloudflare R2

The live map pulls the PMTiles file from Cloudflare R2. Because the file is
~1.5 GB, upload it via the R2 API using multipart upload.

## 1. Find your Cloudflare Account ID

Log in to [dash.cloudflare.com](https://dash.cloudflare.com), select Account Home then click on the three dots and copy the account ID.
Your **Account ID** is the 32-character hex
string (e.g. `a1b2c3d4e5f6...`). It is **not** your
email address.

## 2. Create an R2 API token

Do **not** use the "Edit Cloudflare Workers" template — it has unrelated permissions.
Instead, create an R2-specific token:

1. In the Cloudflare dashboard, go to **R2 → Manage R2 API Tokens → Create API Token**
2. Set permissions to **Object Read & Write**
3. Scope it to the **vehicletrends** bucket
4. Click **Create API Token**
5. Copy both the **Access Key ID** and **Secret Access Key** — you won't see them again.

## 3. Upload via the S3-compatible API

Cloudflare R2 is S3-compatible. Use the AWS CLI.

### Install / configure AWS CLI

```bash
# If not installed:
brew install awscli
```

Configure a named profile for R2:

```bash
aws configure --profile r2
# AWS Access Key ID:     <Access Key ID from Step 2>
# AWS Secret Access Key: <Secret Access Key from Step 2>
# Default region name:   auto
# Default output format: json
```

### Upload

```bash
aws s3 cp data/hhi_tracts.pmtiles s3://vehicletrends/hhi_tracts.pmtiles \
  --profile r2 \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Replace `<ACCOUNT_ID>` with your 32-character account ID from Step 1.

The file will overwrite the existing object in the bucket. The public URL used
by the map will serve the new version immediately:

```
https://pub-17d608be304c4976845ab692fc09de91.r2.dev/hhi_tracts.pmtiles
```

## 4. Verify

Open the map at the GitHub Pages URL and confirm the new data loads correctly.
You can then delete the API token / revoke the Access Key.
