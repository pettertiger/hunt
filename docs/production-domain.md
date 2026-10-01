# Production domain

Target hostname: `jaga.tiger.nu`  
Registrar and DNS: One.com  
Static hosting: Cloudflare Pages

## Cloudflare Pages project

- Connect the GitHub repository to a Pages project named `jaga-tiger-nu`.
- Build command: `sh scripts/build-pages.sh`
- Build output directory: `dist`
- Use `develop` for preview deployments and `main` for production after release approval.
- Configure build variables for each environment:
  - `SUPABASE_URL`: that environment's Supabase project URL.
  - `SUPABASE_PUBLISHABLE_KEY`: that environment's publishable key, or its legacy anon key.
- Do not add a secret or service-role key. The build script rejects those key types.

The build output contains only the two HTML pages, generated `config.js`, and `_headers`. It intentionally excludes SQL migrations, PDFs, test data, and local files.

## One.com DNS

After Cloudflare Pages has been created and `jaga.tiger.nu` added under the Pages project's Custom domains, copy the exact CNAME target Cloudflare displays into One.com DNS:

- Type: `CNAME`
- Host/name: `jaga`
- Target: the assigned `<pages-project>.pages.dev` hostname

Keep the existing One.com nameservers; no full-zone nameserver migration is required for this subdomain. Cloudflare must verify the record and provision HTTPS before production use.

## Supabase Auth

In the production Supabase project, set the Site URL to `https://jaga.tiger.nu` and allow these redirect URLs:

- `https://jaga.tiger.nu/index.html`
- `https://jaga.tiger.nu/map-editor.html`

Set the corresponding preview URL separately in the development project's Auth URL configuration. Guest links use the active site's URL and keep their token in the URL fragment.
