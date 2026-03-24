/** @type {import('next').NextConfig} */
const nextConfig = {
  // Static export — outputs to /out, served by nginx
  // Trade-off: no SSR/ISR, but no Node.js runtime needed in prod container
  output: 'export',
  trailingSlash: true,
  images: {
    // Static export requires unoptimized images (no Next.js image optimization server)
    unoptimized: true,
  },
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080',
  },
}

module.exports = nextConfig
