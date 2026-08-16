import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        // Served as a static file from public/, but iOS's AASA fetcher
        // expects JSON — the extensionless path otherwise falls back to
        // application/octet-stream.
        source: "/.well-known/apple-app-site-association",
        headers: [{ key: "Content-Type", value: "application/json" }],
      },
    ];
  },
};

export default nextConfig;
