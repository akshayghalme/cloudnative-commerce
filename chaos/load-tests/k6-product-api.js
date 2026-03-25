// k6 Load Test — product-api
//
// Simulates realistic API traffic with staged ramp-up:
//   1. Warm-up: 10 VUs for 1 minute (baseline)
//   2. Ramp-up: 10 → 100 VUs over 3 minutes (gradual load increase)
//   3. Sustained: 100 VUs for 5 minutes (steady-state under load)
//   4. Spike: 100 → 200 VUs for 2 minutes (sudden traffic burst)
//   5. Cool-down: 200 → 0 VUs over 1 minute
//
// Thresholds define pass/fail criteria — the test FAILS if:
//   - P95 latency > 300ms
//   - P99 latency > 500ms (matches SLO from Task 39)
//   - Error rate > 1%
//   - Request rate drops below 50 req/s during sustained phase
//
// Run: k6 run chaos/load-tests/k6-product-api.js
// Run with Prometheus output: k6 run --out experimental-prometheus-rw chaos/load-tests/k6-product-api.js

import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";

// ─── Custom Metrics ──────────────────────────────────────────────────────
const errorRate = new Rate("errors");
const productListLatency = new Trend("product_list_latency", true);
const productDetailLatency = new Trend("product_detail_latency", true);
const healthLatency = new Trend("health_check_latency", true);

// ─── Configuration ───────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || "http://product-api.commerce.svc.cluster.local";

export const options = {
  stages: [
    // Warm-up: establish baseline
    { duration: "1m", target: 10 },
    // Ramp-up: gradual load increase
    { duration: "3m", target: 100 },
    // Sustained: steady-state under load
    { duration: "5m", target: 100 },
    // Spike: sudden traffic burst (2x normal)
    { duration: "2m", target: 200 },
    // Cool-down: graceful ramp-down
    { duration: "1m", target: 0 },
  ],

  thresholds: {
    // Overall HTTP request duration
    http_req_duration: [
      "p(95)<300", // 95% of requests under 300ms
      "p(99)<500", // 99% of requests under 500ms (SLO)
    ],
    // Error rate must stay below 1%
    errors: ["rate<0.01"],
    // Per-endpoint latency thresholds
    product_list_latency: ["p(95)<400"],
    product_detail_latency: ["p(95)<200"],
    health_check_latency: ["p(99)<100"],
    // Minimum request throughput
    http_reqs: ["rate>50"],
  },

  // Tags for Prometheus/Grafana integration
  tags: {
    testid: "product-api-load",
    environment: __ENV.ENVIRONMENT || "dev",
  },
};

// ─── Test Scenarios ──────────────────────────────────────────────────────
export default function () {
  // Simulate realistic user behavior with weighted endpoints:
  // 50% browse products, 30% view product detail, 15% search, 5% health
  const rand = Math.random();

  if (rand < 0.5) {
    listProducts();
  } else if (rand < 0.8) {
    getProductDetail();
  } else if (rand < 0.95) {
    searchProducts();
  } else {
    healthCheck();
  }

  // Think time — real users don't hammer endpoints continuously.
  // Random 1-3 seconds simulates human browsing behavior.
  sleep(Math.random() * 2 + 1);
}

// ─── Endpoint Functions ──────────────────────────────────────────────────

function listProducts() {
  group("List Products", function () {
    const params = {
      headers: { "Content-Type": "application/json" },
      tags: { endpoint: "list_products" },
    };

    const res = http.get(`${BASE_URL}/api/v1/products?page=1&limit=20`, params);

    productListLatency.add(res.timings.duration);

    const success = check(res, {
      "list products: status 200": (r) => r.status === 200,
      "list products: has items": (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.products && body.products.length > 0;
        } catch {
          return false;
        }
      },
      "list products: latency < 400ms": (r) => r.timings.duration < 400,
    });

    errorRate.add(!success);
  });
}

function getProductDetail() {
  group("Product Detail", function () {
    // Rotate through product IDs 1-100
    const productId = Math.floor(Math.random() * 100) + 1;
    const params = {
      headers: { "Content-Type": "application/json" },
      tags: { endpoint: "product_detail" },
    };

    const res = http.get(`${BASE_URL}/api/v1/products/${productId}`, params);

    productDetailLatency.add(res.timings.duration);

    const success = check(res, {
      "product detail: status 200 or 404": (r) =>
        r.status === 200 || r.status === 404,
      "product detail: latency < 200ms": (r) => r.timings.duration < 200,
    });

    errorRate.add(!success);
  });
}

function searchProducts() {
  group("Search Products", function () {
    const queries = ["laptop", "phone", "headphones", "keyboard", "monitor"];
    const query = queries[Math.floor(Math.random() * queries.length)];
    const params = {
      headers: { "Content-Type": "application/json" },
      tags: { endpoint: "search_products" },
    };

    const res = http.get(
      `${BASE_URL}/api/v1/products/search?q=${query}`,
      params
    );

    const success = check(res, {
      "search: status 200": (r) => r.status === 200,
      "search: latency < 500ms": (r) => r.timings.duration < 500,
    });

    errorRate.add(!success);
  });
}

function healthCheck() {
  group("Health Check", function () {
    const res = http.get(`${BASE_URL}/healthz`, {
      tags: { endpoint: "healthz" },
    });

    healthLatency.add(res.timings.duration);

    const success = check(res, {
      "healthz: status 200": (r) => r.status === 200,
      "healthz: latency < 50ms": (r) => r.timings.duration < 50,
    });

    errorRate.add(!success);
  });
}

// ─── Teardown ────────────────────────────────────────────────────────────
export function handleSummary(data) {
  return {
    stdout: textSummary(data, { indent: " ", enableColors: true }),
    "load-test-results.json": JSON.stringify(data, null, 2),
  };
}

// k6 built-in text summary
import { textSummary } from "https://jslib.k6.io/k6-summary/0.1.0/index.js";
